import AppKit
import ApplicationServices

struct MappingDiagnostic: Codable, Sendable, Equatable {
    let timestamp: Double
    let device: PenIdentity?
    let targetPID: Int32
    let targetBundleID: String?
    let profileID: UUID?
    let inputPressure: Double
    var outputPressure: Double
    let tabletInputPressure: Double
    var tabletOutputPressure: Double
    let reason: String
    var taper: StrokeTaperDiagnostic? = nil
    var delivery: String = "直接输出"
    var eventType: UInt32? = nil
    var inputPosition: TrajectoryPosition? = nil
    var outputPosition: TrajectoryPosition? = nil
    var smoothing: TrajectorySmoothingDiagnostic? = nil
}

struct MappingSnapshot: Codable, Sendable, Equatable {
    var isRunning = false
    var isStarting = false
    var status = "映射已暂停"
    var modifiedEventCount: UInt64 = 0
    var diagnostics: [MappingDiagnostic] = []
    var activeProfiles: [PressureProfile] = []
    var bufferedEventCount = 0
    var defaults = MappingDefaults()
}

struct PenMappingResult {
    let diagnostic: MappingDiagnostic
    let deviceID: Int
    let profile: PressureProfile?
    let isBeginning: Bool
    let isEnding: Bool
}

/// Owned exclusively by the engine lock (or by a fixture in tests).
struct PressureMappingProcessor {
    private var sessions: [Int: PenIdentity] = [:]
    private var order: [Int] = []
    private struct Stroke {
        let profile: PressureProfile?
        let targetPID: Int32
        var taper = StrokeTaperState()
        var mouseTrajectory = TrajectorySmoothingState()
        var tabletTrajectory = TrajectorySmoothingState()
    }
    private var strokes: [Int: Stroke] = [:]
    private(set) var profiles: [PressureProfile] = []
    var applications: [Int32: String] = [:]
    var defaults = MappingDefaults()
    var snapshot = MappingSnapshot()

    mutating func setProfiles(_ updated: [PressureProfile]) {
        let enabledDevices = Set(updated.map(\.device))
        // A disabled stroke stays passthrough even if that device is enabled again before lift-off.
        for (id, stroke) in strokes {
            if let profile = stroke.profile, !enabledDevices.contains(profile.device) {
                strokes[id] = Stroke(profile: nil, targetPID: stroke.targetPID)
            }
        }
        profiles = updated
        snapshot.activeProfiles = updated
    }
    mutating func disable() { profiles = []; strokes = [:]; sessions = [:]; order = []; snapshot.activeProfiles = [] }
    @discardableResult mutating func process(_ event: CGEvent, recordDiagnostic: Bool = true) -> PenMappingResult? {
        // Plain mouse-up can terminate a pen stroke even when its tablet subtype is absent.
        let up = [CGEventType.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(event.type)
        if up { deferEnd(event) }
        let mouseTypes: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged]
        let mouse = mouseTypes.contains(event.type)
        let subtype = mouse ? event.getIntegerValueField(.mouseEventSubtype) : 0
        let proximity = event.type == .tabletProximity || (mouse && subtype == 2)
        let point = event.type == .tabletPointer || (mouse && subtype == 1)
        guard proximity || point else { return nil }
        let id = Int(event.getIntegerValueField(proximity ? .tabletProximityEventDeviceID : .tabletEventDeviceID))
        if proximity {
            if event.getIntegerValueField(.tabletProximityEventEnterProximity) != 0 {
                let tool: String
                switch event.getIntegerValueField(.tabletProximityEventPointerType) {
                case 1: tool = "笔"
                case 2: tool = "数位板光标"
                case 3: tool = "橡皮擦"
                default: tool = "未知工具"
                }
                func integer(_ field: CGEventField) -> Int { Int(event.getIntegerValueField(field)) }
                let info = PenDeviceInfo(vendorID: integer(.tabletProximityEventVendorID), tabletID: integer(.tabletProximityEventTabletID),
                    pointingDeviceID: integer(.tabletProximityEventPointerID), systemTabletID: integer(.tabletProximityEventSystemTabletID),
                    vendorPointingDeviceType: integer(.tabletProximityEventVendorPointerType), serialNumber: integer(.tabletProximityEventVendorPointerSerialNumber),
                    uniqueID: UInt64(bitPattern: event.getIntegerValueField(.tabletProximityEventVendorUniqueID)),
                    capabilityMask: integer(.tabletProximityEventCapabilityMask), toolType: tool)
                if sessions[id] == nil { order.append(id) }
                let identity = PenIdentity.resolve(info: info, deviceID: id)
                if sessions[id] != identity { strokes[id] = nil }
                sessions[id] = identity
                while order.count > 128 { let old = order.removeFirst(); sessions[old] = nil; strokes[old] = nil }
            } else { sessions[id] = nil; strokes[id] = nil; order.removeAll { $0 == id } }
            return nil
        }
        guard event.type != .mouseMoved else { return nil }
        let field: CGEventField = mouse ? .mouseEventPressure : .tabletEventPointPressure
        let inputPosition = event.location
        let input = event.getDoubleValueField(field)
        let tabletInput = event.getDoubleValueField(.tabletEventPointPressure)
        guard input.isFinite, tabletInput.isFinite else { return nil }
        let identity = sessions[id]
        let pid = Int32(clamping: event.getIntegerValueField(.eventTargetUnixProcessID))
        let bundle = applications[pid]
        let down = [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
        // Capture even a passthrough decision, so enabling a profile cannot alter a stroke midway.
        // An untargeted standalone packet must not block the later application mouse-down.
        let untargetedPrelude = down && strokes[id].map { $0.targetPID != pid && applications[$0.targetPID] == nil } == true
        let beginning = !up && ((strokes[id] == nil && (down || max(input, tabletInput) > 0)) || untargetedPrelude)
        let ending = up || (!down && max(input, tabletInput) == 0)
        if beginning {
            let candidate = profiles.first { $0.device == identity && bundle.map($0.effectiveTargetBundleIDs.contains) == true }
            let match = candidate.flatMap { profile in bundle.flatMap { defaults.resolve(profile, bundleID: $0) } }
            if strokes.count >= 128, let evicted = strokes.keys.first { strokes[evicted] = nil }
            strokes[id] = Stroke(profile: match, targetPID: pid)
        }
        let stroke = strokes[id]
        // Immediate disable overrides any curve latched at stroke start.
        let profile = stroke?.profile.flatMap { old in profiles.contains(where: { $0.device == old.device }) ? old : nil }
        let allowed = profile != nil && stroke?.targetPID == pid && bundle.map { profile!.effectiveTargetBundleIDs.contains($0) } == true
        let curvePressure = allowed ? profile!.curve.map(input) : input
        let tabletCurvePressure = allowed ? profile!.curve.map(tabletInput) : tabletInput
        var requested = curvePressure
        var tabletRequested = tabletCurvePressure
        var taperDiagnostic: StrokeTaperDiagnostic?
        if allowed, let profile, profile.taper.entryEnabled || profile.taper.exitEnabled, var current = strokes[id] {
            let result = current.taper.apply(settings: profile.taper, input: input, tabletInput: tabletInput,
                curvePressure: curvePressure, tabletCurvePressure: tabletCurvePressure,
                timestamp: Double(event.timestamp)/1_000_000_000, location: event.location, isEnding: ending)
            requested = result.pressure; tabletRequested = result.tabletPressure
            taperDiagnostic = result.diagnostic
            strokes[id] = current
        }
        if allowed {
            // Map the two pressure fields independently: mouse pressure can have lower precision.
            // Skip identical writes so a linear profile is an exact passthrough.
            if abs(tabletRequested-tabletInput) > 1e-12 { event.setDoubleValueField(.tabletEventPointPressure, value: tabletRequested) }
            if mouse && abs(requested-input) > 1e-12 { event.setDoubleValueField(.mouseEventPressure, value: requested) }
        }
        if !allowed, var current = strokes[id] {
            current.mouseTrajectory = .init(); current.tabletTrajectory = .init()
            strokes[id] = current
        }
        var smoothingDiagnostic: TrajectorySmoothingDiagnostic?
        func roundedInteger(_ value: Double) -> Int64 {
            guard value.isFinite else { return 0 }
            if value >= Double(Int64.max) { return Int64.max }
            if value <= Double(Int64.min) { return Int64.min }
            return Int64(value.rounded())
        }
        let primaryMouse = [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type)
        let primaryTablet = event.type == .tabletPointer && event.getIntegerValueField(.tabletEventPointButtons) & ~1 == 0
        if allowed, let profile, profile.smoothing.enabled, profile.smoothing.strength > 0,
           primaryMouse || primaryTablet, var current = strokes[id] {
            let inputTablet = CGPoint(x: Double(event.getIntegerValueField(.tabletEventPointX)),
                                      y: Double(event.getIntegerValueField(.tabletEventPointY)))
            var filter = mouse ? current.mouseTrajectory : current.tabletTrajectory
            let previous = filter.hasValue ? filter.screen : inputPosition
            let filtered = filter.apply(screen: inputPosition, tablet: inputTablet,
                timestamp: Double(event.timestamp)/1_000_000_000, settings: profile.smoothing, ending: ending)
            // Keep routing-sensitive button boundaries intact at the annotated tap.
            // The initial sample seeds the filter; only contact movement is rewritten.
            if !down && !ending && filtered.screen.x.isFinite && filtered.screen.y.isFinite
                && (filtered.screen != inputPosition || filtered.tablet != inputTablet) {
                event.location = filtered.screen
                event.setIntegerValueField(.tabletEventPointX, value: roundedInteger(filtered.tablet.x))
                event.setIntegerValueField(.tabletEventPointY, value: roundedInteger(filtered.tablet.y))
                if mouse {
                    event.setIntegerValueField(.mouseEventDeltaX, value: roundedInteger(filtered.screen.x-previous.x))
                    event.setIntegerValueField(.mouseEventDeltaY, value: roundedInteger(filtered.screen.y-previous.y))
                }
            }
            smoothingDiagnostic = .init(enabled: true, strength: profile.smoothing.strength,
                inputTablet: .init(inputTablet), outputTablet: .init(CGPoint(
                    x: Double(event.getIntegerValueField(.tabletEventPointX)),
                    y: Double(event.getIntegerValueField(.tabletEventPointY)))))
            if mouse { current.mouseTrajectory = filter } else { current.tabletTrajectory = filter }
            strokes[id] = current
        }
        let output = event.getDoubleValueField(field)
        let tabletOutput = event.getDoubleValueField(.tabletEventPointPressure)
        let reason = allowed ? "已应用曲线" : identity == nil ? "等待 proximity 识别设备" : bundle == nil ? "目标应用未知" : "设备或应用未启用配置 / 本笔透传"
        var diagnostic = MappingDiagnostic(timestamp: Double(event.timestamp)/1_000_000_000, device: identity,
            targetPID: pid, targetBundleID: bundle, profileID: allowed ? profile?.id : nil,
            inputPressure: input, outputPressure: output, tabletInputPressure: tabletInput,
            tabletOutputPressure: tabletOutput, reason: reason, taper: taperDiagnostic)
        diagnostic.eventType = event.type.rawValue
        diagnostic.inputPosition = .init(inputPosition); diagnostic.outputPosition = .init(event.location)
        diagnostic.smoothing = smoothingDiagnostic
        if recordDiagnostic { record(diagnostic) }
        if ending { strokes[id] = nil }
        return PenMappingResult(diagnostic: diagnostic, deviceID: id, profile: allowed ? profile : nil,
                                isBeginning: beginning, isEnding: ending)
    }

    mutating func record(_ diagnostic: MappingDiagnostic) {
        if diagnostic.inputPressure != diagnostic.outputPressure || diagnostic.tabletInputPressure != diagnostic.tabletOutputPressure || diagnostic.inputPosition != diagnostic.outputPosition || diagnostic.smoothing.map({ $0.inputTablet != $0.outputTablet }) == true {
            snapshot.modifiedEventCount += 1
        }
        snapshot.diagnostics.append(diagnostic)
        if snapshot.diagnostics.count > 500 { snapshot.diagnostics.removeFirst(snapshot.diagnostics.count-500) }
    }
    private mutating func deferEnd(_ event: CGEvent) {
        // Clear after processing a tablet up; plain releases carry no tablet device ID.
        if event.getIntegerValueField(.mouseEventSubtype) != 1 { strokes.removeAll() }
    }
}

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

// Experimental, independent of pressure mapping. Only public touch-tagged right clicks qualify.
struct TouchRightClickDiagnostic: Codable, Sendable, Equatable {
    let timestamp: Double
    let type: UInt32
    let subtype: Int64
    let eventNumber: Int64
    let sourcePID: Int64
    let targetPID: Int32
    let targetBundleID: String?
    let suppressed: Bool
}

struct TouchRightClickSnapshot: Codable, Sendable, Equatable {
    var enabled = false
    var isRunning = false
    var isStarting = false
    var status = "实验功能已关闭"
    var targetBundleIDs: [String] = []
    var observedCount: UInt64 = 0
    var suppressedPressCount: UInt64 = 0
    var suppressedEventCount: UInt64 = 0
    var diagnostics: [TouchRightClickDiagnostic] = []
}

struct TouchRightClickFilter {
    private struct Sequence: Equatable {
        let source: Int64
        let number: Int64
    }
    private var blocked: [Sequence] = []
    var applications: [Int32: String] = [:]
    var snapshot = TouchRightClickSnapshot()

    mutating func configure(enabled: Bool, targets: [String], applications: [Int32: String]) {
        snapshot.enabled = enabled; snapshot.targetBundleIDs = targets
        self.applications = applications
        // Existing suppressed sequences still consume their matching release after disabling.
    }
    mutating func clear() {
        snapshot.observedCount = 0; snapshot.suppressedPressCount = 0
        snapshot.suppressedEventCount = 0; snapshot.diagnostics = []
    }
    mutating func resetSequences() { blocked = [] }
    mutating func suppress(_ event: CGEvent) -> Bool {
        guard [.rightMouseDown, .rightMouseDragged, .rightMouseUp].contains(event.type) else { return false }
        let subtype = event.getIntegerValueField(.mouseEventSubtype)
        let key = Sequence(source: event.getIntegerValueField(.eventSourceUnixProcessID), number: event.getIntegerValueField(.mouseEventNumber))
        let pid = Int32(clamping: event.getIntegerValueField(.eventTargetUnixProcessID))
        let bundle = applications[pid]
        var suppress = false
        if event.type == .rightMouseDown {
            // A fresh down with a reused key must not inherit a stale suppression decision.
            blocked.removeAll { $0 == key }
            // Never infer touch from a foreground app, screen position, or recent Pencil use.
            if snapshot.enabled, !event.flags.contains(.maskControl), subtype == Int64(NSEvent.EventSubtype.touch.rawValue),
               let bundle, snapshot.targetBundleIDs.contains(bundle), blocked.count < 8 {
                if !blocked.contains(key) { blocked.append(key) }
                suppress = true; snapshot.suppressedPressCount += 1
            }
        } else if let index = blocked.firstIndex(of: key), subtype != 1, subtype != 2,
                  key.number != 0 || subtype == Int64(NSEvent.EventSubtype.touch.rawValue) {
            // With no event number, don't consume an untagged physical mouse release.
            suppress = true
            if event.type == .rightMouseUp { blocked.remove(at: index) }
        }
        snapshot.observedCount += 1
        if suppress { snapshot.suppressedEventCount += 1 }
        snapshot.diagnostics.append(.init(timestamp: Double(event.timestamp)/1_000_000_000, type: event.type.rawValue,
            subtype: subtype, eventNumber: key.number, sourcePID: key.source, targetPID: pid,
            targetBundleID: bundle, suppressed: suppress))
        if snapshot.diagnostics.count > 500 { snapshot.diagnostics.removeFirst(snapshot.diagnostics.count - 500) }
        return suppress
    }
}

final class TouchRightClickEngine: @unchecked Sendable {
    typealias TapFactory = PressureRemappingEngine.TapFactory
    private let createTap: TapFactory
    private let lock = NSLock()
    private var filter = TouchRightClickFilter()
    private var generation: UInt64 = 0
    private var loop: CFRunLoop?
    init(createTap: @escaping TapFactory = { mask, callback, context in
        CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: context)
    }) { self.createTap = createTap }
    func snapshot() -> TouchRightClickSnapshot { lock.lock(); defer { lock.unlock() }; return filter.snapshot }
    func configure(enabled: Bool, targets: [String], applications: [Int32: String]) {
        lock.lock(); defer { lock.unlock() }
        filter.configure(enabled: enabled, targets: targets, applications: applications)
        if filter.snapshot.isRunning { filter.snapshot.status = enabled ? "实验拦截已开启 · 等待带触摸标记的右键" : "已关闭 · 已拦截序列的抬起仍会收尾" }
    }
    func clearDiagnostics() { lock.lock(); defer { lock.unlock() }; filter.clear() }
    func start() {
        lock.lock()
        guard !filter.snapshot.isRunning, !filter.snapshot.isStarting else { lock.unlock(); return }
        generation += 1; let token = generation
        filter.snapshot.isStarting = true; filter.snapshot.status = "正在创建触摸右键 tap…"
        lock.unlock()
        Thread.detachNewThread { [self] in run(token: token) }
    }
    func stop(reason: String = "实验功能已停止") { halt(reason: reason) }
    private func halt(reason: String, token: UInt64? = nil) {
        lock.lock()
        if let token, token != generation { lock.unlock(); return }
        generation += 1
        filter.snapshot.enabled = false; filter.snapshot.isRunning = false; filter.snapshot.isStarting = false
        filter.snapshot.status = reason; filter.resetSequences()
        let current = loop
        lock.unlock()
        if let current { CFRunLoopStop(current) }
    }
    private final class Context {
        let engine: TouchRightClickEngine
        let token: UInt64
        init(_ engine: TouchRightClickEngine, _ token: UInt64) { self.engine = engine; self.token = token }
    }
    private func run(token: UInt64) {
        let mask = [CGEventType.rightMouseDown, .rightMouseUp, .rightMouseDragged].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let context = Context(self, token)
        guard let tap = createTap(mask, { _, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            let context = Unmanaged<Context>.fromOpaque(pointer).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                context.engine.halt(reason: "系统停用了触摸右键 tap，请手动重新开启", token: context.token)
                return Unmanaged.passUnretained(event)
            }
            return context.engine.handle(event, token: context.token)
        }, Unmanaged.passUnretained(context).toOpaque()) else {
            halt(reason: "无法创建触摸右键 tap，请检查辅助功能权限后重试", token: token); return
        }
        let current = CFRunLoopGetCurrent()!
        guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            CFMachPortInvalidate(tap); halt(reason: "无法创建触摸右键事件源", token: token); return
        }
        lock.lock()
        guard generation == token else { lock.unlock(); CFMachPortInvalidate(tap); return }
        loop = current; filter.snapshot.isStarting = false; filter.snapshot.isRunning = true
        filter.snapshot.status = filter.snapshot.enabled ? "实验拦截已开启 · 等待带触摸标记的右键" : "实验功能已关闭"
        CFRunLoopAddSource(current, source, .commonModes); CGEvent.tapEnable(tap: tap, enable: true)
        lock.unlock()
        withExtendedLifetime(context) { CFRunLoopRun() }
        CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap)
        CFRunLoopRemoveSource(current, source, .commonModes)
        halt(reason: "触摸右键事件线程已结束，请手动重新开启", token: token)
        lock.lock(); if loop === current { loop = nil }; lock.unlock()
    }
    private func handle(_ event: CGEvent, token: UInt64) -> Unmanaged<CGEvent>? {
        lock.lock(); defer { lock.unlock() }
        guard generation == token, filter.snapshot.isRunning,
              event.getIntegerValueField(.eventSourceUserData) != PressureRemappingEngine.replayMarker else { return Unmanaged.passUnretained(event) }
        return filter.suppress(event) ? nil : Unmanaged.passUnretained(event)
    }
}
