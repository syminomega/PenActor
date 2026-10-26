import AppKit
import ApplicationServices

/// All mutable state and the runloop pointer are protected by lock. No UI work in callbacks.
final class PressureRemappingEngine: @unchecked Sendable {
    typealias TapFactory = @Sendable (CGEventMask, CGEventTapCallBack, UnsafeMutableRawPointer) -> CFMachPort?
    private let createTap: TapFactory
    init(createTap: @escaping TapFactory = { mask, callback, context in
        CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .tailAppendEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: context)
    }) { self.createTap = createTap }
    private let lock = NSLock()
    private let outputLock = NSLock()
    private var buffer = BufferedPenEvents()
    static let replayMarker: Int64 = 0x50454E4143544F52
    private var processor = PressureMappingProcessor()
    private var loop: CFRunLoop?
    private var generation: UInt64 = 0

    func snapshot() -> MappingSnapshot { lock.lock(); defer { lock.unlock() }; return processor.snapshot }
    func update(profiles: [PressureProfile], applications: [Int32: String], defaults: MappingDefaults = MappingDefaults()) {
        outputLock.lock(); defer { outputLock.unlock() }
        lock.lock()
        let removed = Set(processor.profiles.map(\.device)).subtracting(profiles.map(\.device))
        let output = removed.isEmpty ? [] : buffer.cancel(devices: removed)
        prepare(output, delivery: "禁用后排空")
        processor.setProfiles(profiles)
        processor.defaults = defaults
        processor.snapshot.defaults = defaults
        processor.applications = applications
        processor.snapshot.activeProfiles = profiles
        processor.snapshot.bufferedEventCount = buffer.count
        lock.unlock()
        post(output)
    }
    func clearDiagnostics() { lock.lock(); defer { lock.unlock() }; processor.snapshot.diagnostics = []; processor.snapshot.modifiedEventCount = 0 }
    func start() {
        lock.lock()
        guard !processor.snapshot.isStarting && !processor.snapshot.isRunning else { lock.unlock(); return }
        processor.snapshot.isStarting = true; generation += 1
        let token = generation
        processor.snapshot.status = "正在创建事件 tap…"
        lock.unlock()
        Thread.detachNewThread { [self] in run(token: token) }
    }
    func stop(reason: String = "映射已暂停") { halt(reason: reason) }

    private func halt(reason: String, token: UInt64? = nil) {
        outputLock.lock(); defer { outputLock.unlock() }
        lock.lock()
        if let token, token != generation { lock.unlock(); return }
        generation += 1; processor.snapshot.isStarting = false
        processor.snapshot.isRunning = false; processor.snapshot.status = reason
        let output = buffer.cancel()
        prepare(output, delivery: "停止后排空")
        processor.snapshot.bufferedEventCount = 0
        processor.disable()
        let currentLoop = loop
        lock.unlock()
        post(output)
        if let currentLoop { CFRunLoopStop(currentLoop) }
    }
    private func run(token: UInt64) {
        let types: [CGEventType] = [.tabletPointer, .tabletProximity, .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged, .keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callbackContext = TapContext(engine: self, generation: token)
        let context = Unmanaged.passUnretained(callbackContext).toOpaque()
        guard let tap = createTap(mask, { _, type, event, context in
                guard let pointer = context else { return Unmanaged.passUnretained(event) }
                let context = Unmanaged<TapContext>.fromOpaque(pointer).takeUnretainedValue()
                let engine = context.engine
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    engine.handleDisabled(token: context.generation)
                    return Unmanaged.passUnretained(event)
                }
                if event.getIntegerValueField(.eventSourceUserData) == PressureRemappingEngine.replayMarker {
                    return Unmanaged.passUnretained(event)
                }
                return engine.handle(event, token: context.generation)
            }, context) else {
                lock.lock()
                if generation == token { processor.snapshot.isStarting = false; processor.disable(); processor.snapshot.status = "无法创建事件 tap，请检查辅助功能权限" }
                lock.unlock(); return
            }
        let current = CFRunLoopGetCurrent()!
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)!
        let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent()+0.002, 0.002, 0, 0) { [weak self] _ in
            self?.pump(token: token)
        }!
        lock.lock()
        guard token == generation else { lock.unlock(); CFMachPortInvalidate(tap); return }
        loop = current; processor.snapshot.isStarting = false
        processor.snapshot.isRunning = true; processor.snapshot.status = "正在映射（等待匹配事件）"
        CFRunLoopAddSource(current, source, .commonModes)
        CFRunLoopAddTimer(current, timer, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lock.unlock()
        withExtendedLifetime(callbackContext) { CFRunLoopRun() }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        CFRunLoopRemoveSource(current, source, .commonModes)
        CFRunLoopTimerInvalidate(timer)
        CFRunLoopRemoveTimer(current, timer, .commonModes)
        halt(reason: "事件线程已结束；映射已停止，请手动重新启用", token: token)
        lock.lock()
        if loop === current { loop = nil }
        lock.unlock()
    }
    private final class TapContext {
        let engine: PressureRemappingEngine
        let generation: UInt64
        init(engine: PressureRemappingEngine, generation: UInt64) { self.engine = engine; self.generation = generation }
    }
    private func handleDisabled(token: UInt64) {
        halt(reason: "系统停用了事件 tap；映射已停止，请手动重新启用", token: token)
    }
    private func handle(_ event: CGEvent, token: UInt64) -> Unmanaged<CGEvent>? {
        outputLock.lock(); defer { outputLock.unlock() }
        lock.lock()
        guard processor.snapshot.isRunning, token == generation else { lock.unlock(); return Unmanaged.passUnretained(event) }
        guard let original = event.copy() else { lock.unlock(); return Unmanaged.passUnretained(event) }
        let result = processor.process(event, recordDiagnostic: false)
        let action = buffer.accept(event, original: original, result: result, now: ProcessInfo.processInfo.systemUptime)
        if !action.suppress, let result { processor.record(result.diagnostic) }
        prepare(action.output, delivery: "提前排空 / 保持顺序")
        processor.snapshot.bufferedEventCount = buffer.count
        lock.unlock()
        post(action.output)
        return action.suppress ? nil : Unmanaged.passUnretained(event)
    }
    private func pump(token: UInt64) {
        outputLock.lock(); defer { outputLock.unlock() }
        lock.lock()
        guard token == generation, processor.snapshot.isRunning else { lock.unlock(); return }
        let output = buffer.drain(now: ProcessInfo.processInfo.systemUptime)
        prepare(output, delivery: "延迟输出")
        processor.snapshot.bufferedEventCount = buffer.count
        lock.unlock()
        post(output)
    }
    // Called only while the state lock is held. Values describe final queued output, not a draft.
    private func prepare(_ output: [BufferedPenPacket], delivery: String) {
        for packet in output {
            if var diagnostic = packet.diagnostic {
                if diagnostic.delivery == "直接输出" { diagnostic.delivery = delivery }
                processor.record(diagnostic)
            }
            buffer.didDeliver(packet)
        }
    }
    private func post(_ output: [BufferedPenPacket]) {
        // Mark replays so our own tap (including a later run) never maps or buffers them twice.
        for packet in output {
            packet.event.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
            packet.event.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}
