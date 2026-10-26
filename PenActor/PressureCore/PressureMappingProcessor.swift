import AppKit
import ApplicationServices

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
        let output = event.getDoubleValueField(field)
        let tabletOutput = event.getDoubleValueField(.tabletEventPointPressure)
        let reason = allowed ? "已应用曲线" : identity == nil ? "等待 proximity 识别设备" : bundle == nil ? "目标应用未知" : "设备或应用未启用配置 / 本笔透传"
        let diagnostic = MappingDiagnostic(timestamp: Double(event.timestamp)/1_000_000_000, device: identity,
            targetPID: pid, targetBundleID: bundle, profileID: allowed ? profile?.id : nil,
            inputPressure: input, outputPressure: output, tabletInputPressure: tabletInput,
            tabletOutputPressure: tabletOutput, reason: reason, taper: taperDiagnostic)
        if recordDiagnostic { record(diagnostic) }
        if ending { strokes[id] = nil }
        return PenMappingResult(diagnostic: diagnostic, deviceID: id, profile: allowed ? profile : nil,
                                isBeginning: beginning, isEnding: ending)
    }

    mutating func record(_ diagnostic: MappingDiagnostic) {
        if diagnostic.inputPressure != diagnostic.outputPressure || diagnostic.tabletInputPressure != diagnostic.tabletOutputPressure {
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
