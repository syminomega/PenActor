import AppKit
import ApplicationServices

struct MappingDiagnostic: Codable, Sendable, Equatable {
    let timestamp: Double
    let device: PenIdentity?
    let targetPID: Int32
    let targetBundleID: String?
    let profileID: UUID?
    let inputPressure: Double
    let outputPressure: Double
    let tabletInputPressure: Double
    let tabletOutputPressure: Double
    let reason: String
}

struct MappingSnapshot: Codable, Sendable, Equatable {
    var isRunning = false
    var isStarting = false
    var status = "映射已暂停"
    var modifiedEventCount: UInt64 = 0
    var diagnostics: [MappingDiagnostic] = []
    var activeProfiles: [PressureProfile] = []
}

/// Owned exclusively by the engine lock (or by a fixture in tests).
struct PressureMappingProcessor {
    private var sessions: [Int: PenIdentity] = [:]
    private var order: [Int] = []
    private struct Stroke { let profile: PressureProfile?; let targetPID: Int32 }
    private var strokes: [Int: Stroke] = [:]
    private(set) var profiles: [PressureProfile] = []
    var applications: [Int32: String] = [:]
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
    mutating func process(_ event: CGEvent) {
        // Plain mouse-up can terminate a pen stroke even when its tablet subtype is absent.
        let up = [CGEventType.leftMouseUp, .rightMouseUp, .otherMouseUp].contains(event.type)
        if up { deferEnd(event) }
        let mouseTypes: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged]
        let mouse = mouseTypes.contains(event.type)
        let subtype = mouse ? event.getIntegerValueField(.mouseEventSubtype) : 0
        let proximity = event.type == .tabletProximity || (mouse && subtype == 2)
        let point = event.type == .tabletPointer || (mouse && subtype == 1)
        guard proximity || point else { return }
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
            return
        }
        guard event.type != .mouseMoved else { return }
        let field: CGEventField = mouse ? .mouseEventPressure : .tabletEventPointPressure
        let input = event.getDoubleValueField(field)
        let tabletInput = event.getDoubleValueField(.tabletEventPointPressure)
        guard input.isFinite, tabletInput.isFinite else { return }
        let identity = sessions[id]
        let pid = Int32(clamping: event.getIntegerValueField(.eventTargetUnixProcessID))
        let bundle = applications[pid]
        let down = [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
        // Capture even a passthrough decision, so enabling a profile cannot alter a stroke midway.
        // An untargeted standalone packet must not block the later application mouse-down.
        let untargetedPrelude = down && strokes[id].map { $0.targetPID != pid && applications[$0.targetPID] == nil } == true
        if (strokes[id] == nil && (down || input > 0)) || untargetedPrelude {
            let match = profiles.first { $0.device == identity && bundle.map($0.targetBundleIDs.contains) == true }
            if strokes.count >= 128, let evicted = strokes.keys.first { strokes[evicted] = nil }
            strokes[id] = Stroke(profile: match, targetPID: pid)
        }
        let stroke = strokes[id]
        // Immediate disable overrides any curve latched at stroke start.
        let profile = stroke?.profile.flatMap { old in profiles.contains(where: { $0.device == old.device }) ? old : nil }
        let allowed = profile != nil && stroke?.targetPID == pid && bundle.map { profile!.targetBundleIDs.contains($0) } == true
        let requested = allowed ? profile!.curve.map(input) : input
        let tabletRequested = allowed ? profile!.curve.map(tabletInput) : tabletInput
        if allowed {
            // Map the two pressure fields independently: mouse pressure can have lower precision.
            // Skip identical writes so a linear profile is an exact passthrough.
            if abs(tabletRequested-tabletInput) > 1e-12 { event.setDoubleValueField(.tabletEventPointPressure, value: tabletRequested) }
            if mouse && abs(requested-input) > 1e-12 { event.setDoubleValueField(.mouseEventPressure, value: requested) }
        }
        let output = event.getDoubleValueField(field)
        let tabletOutput = event.getDoubleValueField(.tabletEventPointPressure)
        if output != input || tabletOutput != tabletInput { snapshot.modifiedEventCount += 1 }
        let reason = allowed ? "已应用曲线" : identity == nil ? "等待 proximity 识别设备" : bundle == nil ? "目标应用未知" : "设备或应用未启用配置 / 本笔透传"
        snapshot.diagnostics.append(.init(timestamp: Double(event.timestamp)/1_000_000_000, device: identity,
            targetPID: pid, targetBundleID: bundle, profileID: allowed ? profile?.id : nil,
            inputPressure: input, outputPressure: output, tabletInputPressure: tabletInput, tabletOutputPressure: tabletOutput, reason: reason))
        if snapshot.diagnostics.count > 500 { snapshot.diagnostics.removeFirst(snapshot.diagnostics.count-500) }
        if input == 0 || up { strokes[id] = nil }
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
    private var processor = PressureMappingProcessor()
    private var loop: CFRunLoop?
    private var generation: UInt64 = 0

    func snapshot() -> MappingSnapshot { lock.lock(); defer { lock.unlock() }; return processor.snapshot }
    func update(profiles: [PressureProfile], applications: [Int32: String]) {
        lock.lock(); defer { lock.unlock() }
        processor.setProfiles(profiles)
        processor.applications = applications
        processor.snapshot.activeProfiles = profiles
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
    func stop(reason: String = "映射已暂停") {
        lock.lock()
        generation += 1; processor.snapshot.isStarting = false; processor.disable()
        processor.snapshot.isRunning = false; processor.snapshot.status = reason
        if let loop { CFRunLoopStop(loop) }
        lock.unlock()
    }
    private func run(token: UInt64) {
        let types: [CGEventType] = [.tabletPointer, .tabletProximity, .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callbackContext = TapContext(engine: self, generation: token)
        let context = Unmanaged.passUnretained(callbackContext).toOpaque()
        guard let tap = createTap(mask, { _, type, event, context in
                guard let pointer = context else { return Unmanaged.passUnretained(event) }
                let context = Unmanaged<TapContext>.fromOpaque(pointer).takeUnretainedValue()
                let engine = context.engine
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    engine.handleDisabled(token: context.generation)
                } else { engine.handle(event, token: context.generation) }
                return Unmanaged.passUnretained(event)
            }, context) else {
                lock.lock()
                if generation == token { processor.snapshot.isStarting = false; processor.disable(); processor.snapshot.status = "无法创建事件 tap，请检查辅助功能权限" }
                lock.unlock(); return
            }
        let current = CFRunLoopGetCurrent()!
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)!
        lock.lock()
        guard token == generation else { lock.unlock(); CFMachPortInvalidate(tap); return }
        loop = current; processor.snapshot.isStarting = false
        processor.snapshot.isRunning = true; processor.snapshot.status = "正在映射（等待匹配事件）"
        CFRunLoopAddSource(current, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lock.unlock()
        withExtendedLifetime(callbackContext) { CFRunLoopRun() }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        CFRunLoopRemoveSource(current, source, .commonModes)
        lock.lock()
        if loop === current { loop = nil }
        if generation == token {
            processor.disable(); processor.snapshot.isRunning = false
            processor.snapshot.status = "事件线程已结束；映射已停止，请手动重新启用"
        }
        lock.unlock()
    }
    private final class TapContext {
        let engine: PressureRemappingEngine
        let generation: UInt64
        init(engine: PressureRemappingEngine, generation: UInt64) { self.engine = engine; self.generation = generation }
    }
    private func handleDisabled(token: UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard token == generation else { return }
        generation += 1; processor.snapshot.isStarting = false; processor.disable()
        processor.snapshot.isRunning = false
        processor.snapshot.status = "系统停用了事件 tap；映射已停止，请手动重新启用"
        if let loop { CFRunLoopStop(loop) }
    }
    private func handle(_ event: CGEvent, token: UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard processor.snapshot.isRunning, token == generation else { return }
        processor.process(event)
    }
}
