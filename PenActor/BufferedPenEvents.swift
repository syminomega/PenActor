import AppKit

struct PenEventRoute: Hashable {
    let deviceID: Int
    let pid: Int32
}

struct BufferedPenPacket {
    let original: CGEvent
    let event: CGEvent
    var diagnostic: MappingDiagnostic?
    let route: PenEventRoute
    let contact: UInt64
    let deadline: Double
}

struct PenBufferAction {
    var suppress = false
    var output: [BufferedPenPacket] = []
}

/// A bounded look-ahead queue. No posting or clock queries here: fixtures drive it deterministically.
struct BufferedPenEvents {
    static let limit = 2048
    private struct Contact {
        let token: UInt64
        let profile: PressureProfile
        var ended = false
        var bypass = false
        var hasMouseDown = false
        var mouseUpObserved = false
    }
    private struct PressedButton {
        let event: CGEvent
        let route: PenEventRoute
        let device: PenIdentity?
    }
    private var contacts: [PenEventRoute: Contact] = [:]
    private var pending: [BufferedPenPacket] = []
    private var pressed: [UInt32: PressedButton] = [:]
    private var sequence: UInt64 = 0
    var count: Int { pending.count }

    mutating func accept(_ event: CGEvent, original: CGEvent, result: PenMappingResult?, now: Double) -> PenBufferAction {
        if let result {
            let route = PenEventRoute(deviceID: result.deviceID, pid: result.diagnostic.targetPID)
            if result.isBeginning, let profile = result.profile, profile.taper.exitEnabled,
               contacts[route] == nil || contacts[route]?.ended == true {
                if contacts.count >= 128 && contacts[route] == nil {
                    return interrupt(with: event, original: original)
                }
                sequence &+= 1
                contacts[route] = Contact(token: sequence, profile: profile)
            }
            guard let contact = contacts[route] else {
                if contacts.keys.contains(where: { $0.deviceID == route.deviceID && $0.pid != route.pid && contacts[$0]?.bypass == false }) {
                    return interrupt(with: event, original: original, releaseButtons: true)
                }
                if !pending.isEmpty && Self.isOrderingBoundary(event.type) { return interrupt(with: event, original: original) }
                observeDirect(event); return PenBufferAction()
            }
            if contact.bypass {
                if result.isEnding { contacts[route] = nil }
                observeDirect(event)
                return PenBufferAction()
            }
            guard let packet = packet(event, original: original, diagnostic: result.diagnostic, route: route, contact: contact, now: now) else {
                return interrupt(with: event, original: original)
            }
            pending.append(packet)
            if Self.downButton(event) != nil { contacts[route]?.hasMouseDown = true }
            if Self.upButton(event) != nil { contacts[route]?.mouseUpObserved = true }
            if result.isEnding && !contact.ended {
                finish(route, endTimestamp: Double(event.timestamp)/1_000_000_000)
            } else if result.isEnding {
                // A companion mouse-up can follow the first zero-pressure tablet packet.
                taperPacket(at: pending.count-1, factor: 0)
            }
            if pending.count >= Self.limit { return interrupt() }
            return PenBufferAction(suppress: true)
        }
        // Keep hover and proximity packets behind the delayed contact events for this pen.
        if let deviceID = ancillaryDevice(event),
           let route = ancillaryRoute(event, deviceID: deviceID),
           let contact = contacts[route] {
            guard let packet = packet(event, original: original, diagnostic: nil, route: route, contact: contact, now: now) else {
                return interrupt(with: event, original: original)
            }
            pending.append(packet)
            if isProximityExit(event) && !contact.ended {
                // A disconnect may omit mouse-up entirely. Release buffered / delivered buttons before proximity exit.
                var held = pressed.filter { $0.value.route == route }.mapValues(\.event)
                for previous in pending.dropLast() where previous.route == route {
                    if let button = Self.downButton(previous.event) { held[button] = previous.event }
                    else if let button = Self.upButton(previous.event) { held[button] = nil }
                    else if Self.isPointerPacket(previous.event) { for button in held.keys { held[button] = previous.event } }
                }
                for (button, base) in held {
                    if let release = releasePacket(base: base, route: route, button: button, contact: contact.token, deadline: packet.deadline) {
                        pending.insert(release, at: pending.count-1)
                        contacts[route]?.mouseUpObserved = true
                    }
                }
                finish(route, endTimestamp: Double(event.timestamp)/1_000_000_000)
            }
            if pending.count >= Self.limit { return interrupt() }
            return PenBufferAction(suppress: true)
        }
        // A plain mouse-up may omit tablet metadata. Delay it only for a matching buffered button.
        if let button = Self.upButton(event) {
            let pid = Int32(clamping: event.getIntegerValueField(.eventTargetUnixProcessID))
            let route = pressed[button]?.route ?? pending.last(where: { Self.downButton($0.event) == button && $0.route.pid == pid })?.route
            if let route, route.pid == pid, let contact = contacts[route], !contact.bypass,
               let packet = packet(event, original: original, diagnostic: nil, route: route, contact: contact, now: now) {
                pending.append(packet)
                contacts[route]?.mouseUpObserved = true
                if !contact.ended { finish(route, endTimestamp: Double(event.timestamp)/1_000_000_000) }
                return PenBufferAction(suppress: true)
            }
        }
        if !pending.isEmpty && Self.isOrderingBoundary(event.type) {
            return interrupt(with: event, original: original)
        }
        observeDirect(event)
        return PenBufferAction()
    }

    mutating func drain(now: Double) -> [BufferedPenPacket] {
        var count = 0
        // Arrival order is authoritative, even if different routes have different delay settings.
        while count < pending.count && pending[count].deadline <= now { count += 1 }
        let output = Array(pending.prefix(count))
        pending.removeFirst(count)
        cleanEndedContacts()
        return output
    }

    /// Restore pending pressure for disabled devices, drain in order, then release their posted buttons.
    mutating func cancel(devices: Set<PenIdentity>? = nil) -> [BufferedPenPacket] {
        var removed = Set(contacts.keys.filter { route in devices == nil || devices!.contains(contacts[route]!.profile.device) })
        for state in pressed.values where devices == nil || state.device.map { devices!.contains($0) } == true { removed.insert(state.route) }
        var output: [BufferedPenPacket] = []
        for var packet in pending {
            if removed.contains(packet.route) {
                packet = restored(packet)
            }
            output.append(packet)
        }
        pending.removeAll()
        // Include pending down/up in the ledger before deciding whether a release is needed.
        for packet in output { didDeliver(packet) }
        for (button, state) in pressed where removed.contains(state.route) {
            if let release = releasePacket(base: state.event, route: state.route, button: button, contact: 0, deadline: 0) {
                output.append(release)
            }
            pressed[button] = nil
        }
        for route in removed { contacts[route] = nil }
        return output
    }

    mutating func didDeliver(_ packet: BufferedPenPacket) {
        if let button = Self.downButton(packet.event) {
            pressed[button] = PressedButton(event: packet.event, route: packet.route, device: packet.diagnostic?.device)
        } else if let button = Self.upButton(packet.event) {
            pressed[button] = nil
        } else if Self.isPointerPacket(packet.event) {
            for (button, state) in pressed where state.route == packet.route {
                pressed[button] = PressedButton(event: packet.event, route: packet.route, device: state.device)
            }
        }
    }

    private func packet(_ event: CGEvent, original: CGEvent, diagnostic: MappingDiagnostic?, route: PenEventRoute,
                        contact: Contact, now: Double) -> BufferedPenPacket? {
        guard let copy = event.copy() else { return nil }
        if Self.upButton(event) != nil {
            copy.setDoubleValueField(.mouseEventPressure, value: 0)
            copy.setDoubleValueField(.tabletEventPointPressure, value: 0)
        }
        return .init(original: original, event: copy, diagnostic: diagnostic, route: route, contact: contact.token,
                     deadline: now+contact.profile.taper.exitDurationMS/1000)
    }

    private mutating func finish(_ route: PenEventRoute, endTimestamp: Double) {
        guard let contact = contacts[route] else { return }
        contacts[route]?.ended = true
        let duration = contact.profile.taper.exitDurationMS/1000
        for i in pending.indices where pending[i].route == route && pending[i].contact == contact.token {
            let time = Double(pending[i].event.timestamp)/1_000_000_000
            let t = min(1, max(0, (endTimestamp-time)/duration))
            taperPacket(at: i, factor: t*t*(3-2*t))
        }
    }

    private mutating func taperPacket(at index: Int, factor: Double) {
        guard var diagnostic = pending[index].diagnostic else { return }
        let event = pending[index].event
        let base = diagnostic.taper.map { $0.curvePressure*$0.entryFactor } ?? diagnostic.outputPressure
        let tabletBase = diagnostic.taper.map { $0.tabletCurvePressure*$0.entryFactor } ?? diagnostic.tabletOutputPressure
        event.setDoubleValueField(.tabletEventPointPressure, value: tabletBase*factor)
        if event.type != .tabletPointer { event.setDoubleValueField(.mouseEventPressure, value: base*factor) }
        diagnostic.outputPressure = event.getDoubleValueField(event.type == .tabletPointer ? .tabletEventPointPressure : .mouseEventPressure)
        diagnostic.tabletOutputPressure = event.getDoubleValueField(.tabletEventPointPressure)
        if let taper = diagnostic.taper {
            diagnostic.taper = .init(curvePressure: taper.curvePressure, tabletCurvePressure: taper.tabletCurvePressure,
                entryFactor: taper.entryFactor, exitFactor: factor, tabletExitFactor: factor,
                distance: taper.distance, elapsedMS: taper.elapsedMS, phase: "出锋 / 尾部修整")
        }
        pending[index].diagnostic = diagnostic
    }

    private func restored(_ packet: BufferedPenPacket) -> BufferedPenPacket {
        var diagnostic = packet.diagnostic
        if let old = diagnostic {
            diagnostic = MappingDiagnostic(timestamp: old.timestamp, device: old.device, targetPID: old.targetPID,
                targetBundleID: old.targetBundleID, profileID: nil, inputPressure: old.inputPressure,
                outputPressure: old.inputPressure, tabletInputPressure: old.tabletInputPressure,
                tabletOutputPressure: old.tabletInputPressure, reason: "暂停 / 禁用：缓存恢复原输入", delivery: "取消缓冲")
            diagnostic?.eventType = old.eventType
            diagnostic?.inputPosition = old.inputPosition; diagnostic?.outputPosition = old.inputPosition
            if var smoothing = old.smoothing {
                smoothing.enabled = false; smoothing.outputTablet = smoothing.inputTablet
                diagnostic?.smoothing = smoothing
            }
        }
        return .init(original: packet.original, event: packet.original, diagnostic: diagnostic, route: packet.route,
                     contact: packet.contact, deadline: packet.deadline)
    }

    private mutating func interrupt(with event: CGEvent? = nil, original: CGEvent? = nil, releaseButtons: Bool = false) -> PenBufferAction {
        var output = pending
        pending.removeAll()
        for route in contacts.keys { contacts[route]?.bypass = true }
        if releaseButtons || event.map({ Self.downButton($0) != nil }) == true {
            for packet in output { didDeliver(packet) }
            for (button, state) in pressed {
                if let release = releasePacket(base: state.event, route: state.route, button: button, contact: 0, deadline: 0) { output.append(release) }
                pressed[button] = nil
            }
        }
        if let event, let original, let copy = event.copy() {
            output.append(.init(original: original, event: copy, diagnostic: nil,
                route: .init(deviceID: -1, pid: Int32(clamping: event.getIntegerValueField(.eventTargetUnixProcessID))), contact: 0, deadline: 0))
        }
        return PenBufferAction(suppress: true, output: output)
    }

    private mutating func cleanEndedContacts() {
        let retained = Set(pending.map(\.contact))
        for route in contacts.keys {
            if let contact = contacts[route], contact.ended, !retained.contains(contact.token),
               !contact.hasMouseDown || contact.mouseUpObserved { contacts[route] = nil }
        }
    }
    private mutating func observeDirect(_ event: CGEvent) {
        let pid = Int32(clamping: event.getIntegerValueField(.eventTargetUnixProcessID))
        if let button = Self.upButton(event), pid == 0 || pressed[button]?.route.pid == pid { pressed[button] = nil }
    }
    private func ancillaryRoute(_ event: CGEvent, deviceID: Int) -> PenEventRoute? {
        let pid = Int32(clamping: event.getIntegerValueField(.eventTargetUnixProcessID))
        let candidates = contacts.keys.filter { $0.deviceID == deviceID && $0.pid != 0 && contacts[$0]?.bypass == false }
        let exact = candidates.filter { $0.pid == pid }
        let active = candidates.filter { contacts[$0]?.ended == false }
        let preferred = !exact.isEmpty ? exact : !active.isEmpty ? active : candidates
        return preferred.max { contacts[$0]!.token < contacts[$1]!.token }
    }
    private func ancillaryDevice(_ event: CGEvent) -> Int? {
        if event.type == .tabletProximity { return Int(event.getIntegerValueField(.tabletProximityEventDeviceID)) }
        if event.type == .mouseMoved {
            switch event.getIntegerValueField(.mouseEventSubtype) {
            case 1: return Int(event.getIntegerValueField(.tabletEventDeviceID))
            case 2: return Int(event.getIntegerValueField(.tabletProximityEventDeviceID))
            default: return nil
            }
        }
        return nil
    }
    private func isProximityExit(_ event: CGEvent) -> Bool {
        (event.type == .tabletProximity || event.getIntegerValueField(.mouseEventSubtype) == 2)
            && event.getIntegerValueField(.tabletProximityEventEnterProximity) == 0
    }
    private func releasePacket(base: CGEvent, route: PenEventRoute, button: UInt32, contact: UInt64, deadline: Double) -> BufferedPenPacket? {
        guard let release = base.copy() else { return nil }
        release.type = Self.upType(button)
        release.setIntegerValueField(.mouseEventSubtype, value: 1)
        release.setIntegerValueField(.tabletEventDeviceID, value: Int64(route.deviceID))
        release.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        release.setDoubleValueField(.mouseEventPressure, value: 0)
        release.setDoubleValueField(.tabletEventPointPressure, value: 0)
        release.setIntegerValueField(.tabletEventPointButtons, value: 0)
        return .init(original: release, event: release, diagnostic: nil, route: route, contact: contact, deadline: deadline)
    }
    private static func downButton(_ event: CGEvent) -> UInt32? {
        switch event.type {
        case .leftMouseDown: 0
        case .rightMouseDown: 1
        case .otherMouseDown: max(2, UInt32(clamping: event.getIntegerValueField(.mouseEventButtonNumber)))
        default: nil
        }
    }
    private static func upButton(_ event: CGEvent) -> UInt32? {
        switch event.type {
        case .leftMouseUp: 0
        case .rightMouseUp: 1
        case .otherMouseUp: max(2, UInt32(clamping: event.getIntegerValueField(.mouseEventButtonNumber)))
        default: nil
        }
    }
    private static func upType(_ button: UInt32) -> CGEventType {
        switch button { case 0: .leftMouseUp; case 1: .rightMouseUp; default: .otherMouseUp }
    }
    private static func isPointerPacket(_ event: CGEvent) -> Bool {
        [.tabletPointer, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged].contains(event.type)
    }
    private static func isOrderingBoundary(_ type: CGEventType) -> Bool {
        [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type)
    }
}

