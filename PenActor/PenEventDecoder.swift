import AppKit

enum PenEventDecoder {
    static func decode(_ event: NSEvent, source: EventSource, foregroundApp: String) -> PenEvent? {
        let kind = TabletEventKind.classify(event)
        guard kind != .ignored else { return nil }
        var info: PenDeviceInfo?
        var sample: PenSample?
        var proximity: Bool?
        if kind == .proximity {
            proximity = event.isEnteringProximity
            let tool: String
            switch event.pointingDeviceType {
            case .pen: tool = "笔"
            case .eraser: tool = "橡皮擦"
            case .cursor: tool = "数位板光标"
            default: tool = "未知工具"
            }
            info = PenDeviceInfo(
                vendorID: event.vendorID, tabletID: event.tabletID,
                pointingDeviceID: event.pointingDeviceID, systemTabletID: event.systemTabletID,
                vendorPointingDeviceType: event.vendorPointingDeviceType,
                serialNumber: event.pointingDeviceSerialNumber, uniqueID: event.uniqueID,
                capabilityMask: event.capabilityMask, toolType: tool
            )
        } else {
            sample = PenSample(
                pressure: TabletEventKind.canReadPressure(type: event.type) ? event.pressure : nil,
                tiltX: event.tilt.x, tiltY: event.tilt.y,
                rotation: event.rotation, tangentialPressure: event.tangentialPressure,
                absoluteX: event.absoluteX, absoluteY: event.absoluteY, absoluteZ: event.absoluteZ,
                buttons: event.buttonMask.rawValue
            )
        }
        return PenEvent(
            deviceID: event.deviceID, timestamp: event.timestamp, receivedAt: Date(),
            source: source, typeName: eventName(type: event.type, kind: kind), foregroundApp: foregroundApp,
            proximity: proximity, info: info, sample: sample
        )
    }

    private static func eventName(type: NSEvent.EventType, kind: TabletEventKind) -> String {
        let name: String
        switch type {
        case .tabletPoint: return "tabletPoint"
        case .tabletProximity: return "tabletProximity"
        case .mouseMoved: name = "mouseMoved"
        case .leftMouseDown: name = "leftMouseDown"
        case .leftMouseUp: name = "leftMouseUp"
        case .leftMouseDragged: name = "leftMouseDragged"
        case .rightMouseDown: name = "rightMouseDown"
        case .rightMouseUp: name = "rightMouseUp"
        case .rightMouseDragged: name = "rightMouseDragged"
        case .otherMouseDown: name = "otherMouseDown"
        case .otherMouseUp: name = "otherMouseUp"
        case .otherMouseDragged: name = "otherMouseDragged"
        default: name = "event(\(type.rawValue))"
        }
        return "\(name) · \(kind == .point ? "tabletPoint" : "tabletProximity")"
    }
}
