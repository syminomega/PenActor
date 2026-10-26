import AppKit

enum EventSource: String, Sendable, Codable {
    case local = "本应用"
    case global = "其他应用"

    /// Display labels are localized separately from the legacy Codable raw values.
    var label: String {
        switch self {
        case .local: String(localized: "本应用")
        case .global: String(localized: "其他应用")
        }
    }
}

enum TabletEventKind: Equatable {
    case point, proximity, ignored

    static let mouseTypes: Set<NSEvent.EventType> = [
        .mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
        .otherMouseDown, .otherMouseUp, .otherMouseDragged
    ]

    static func classify(_ event: NSEvent) -> Self {
        // subtype itself throws on standalone tablet events. Read it only on mouse events.
        if event.type == .tabletPoint { return .point }
        if event.type == .tabletProximity { return .proximity }
        guard mouseTypes.contains(event.type) else { return .ignored }
        return classify(type: event.type, subtype: event.subtype)
    }

    static func classify(type: NSEvent.EventType, subtype: NSEvent.EventSubtype) -> Self {
        if type == .tabletPoint { return .point }
        if type == .tabletProximity { return .proximity }
        guard mouseTypes.contains(type) else { return .ignored }
        if subtype == .tabletPoint { return .point }
        if subtype == .tabletProximity { return .proximity }
        return .ignored
    }

    // NSEvent.pressure is NOT valid on mouseMoved, even with a tablet subtype.
    static func canReadPressure(type: NSEvent.EventType) -> Bool {
        [.tabletPoint, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
         .rightMouseDown, .rightMouseUp, .rightMouseDragged,
         .otherMouseDown, .otherMouseUp, .otherMouseDragged].contains(type)
    }
}

struct PenDeviceInfo: Equatable, Codable {
    let vendorID: Int
    let tabletID: Int
    let pointingDeviceID: Int
    let systemTabletID: Int
    let vendorPointingDeviceType: Int
    let serialNumber: Int
    let uniqueID: UInt64
    let capabilityMask: Int
    let toolType: String

    /// Keep toolType unchanged: identity resolution and existing logs use these values.
    var localizedToolType: String {
        switch toolType {
        case "笔": String(localized: "笔")
        case "橡皮擦": String(localized: "橡皮擦")
        case "数位板光标": String(localized: "数位板光标")
        case "未知工具": String(localized: "未知工具")
        default: toolType
        }
    }
}

enum PenCapability: Int {
    // Public SDK: IOKit/hidsystem/IOLLEvent.h NX_TABLET_CAPABILITY_*MASK.
    case absoluteX = 0x0002, absoluteY = 0x0004, buttons = 0x0040
    case tiltX = 0x0080, tiltY = 0x0100, absoluteZ = 0x0200
    case pressure = 0x0400, tangentialPressure = 0x0800, rotation = 0x2000

    func support(mask: Int?) -> String {
        guard let mask, mask != 0 else { return String(localized: "支持情况未知") }
        return mask & rawValue != 0 ? String(localized: "驱动声明支持") : String(localized: "驱动未声明支持")
    }
}

/// System event values, after any driver processing. Missing pressure is distinct from zero.
struct PenSample: Equatable, Codable {
    let pressure: Float?
    let tiltX: Double
    let tiltY: Double
    let rotation: Float
    let tangentialPressure: Float
    let absoluteX: Int
    let absoluteY: Int
    let absoluteZ: Int
    let buttons: UInt

    enum CodingKeys: String, CodingKey {
        case pressure, tiltX, tiltY, rotation, tangentialPressure
        case absoluteX, absoluteY, absoluteZ, buttons
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Explicit null is important: an unreadable pressure is not zero pressure.
        try container.encode(pressure, forKey: .pressure)
        try container.encode(tiltX, forKey: .tiltX)
        try container.encode(tiltY, forKey: .tiltY)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(tangentialPressure, forKey: .tangentialPressure)
        try container.encode(absoluteX, forKey: .absoluteX)
        try container.encode(absoluteY, forKey: .absoluteY)
        try container.encode(absoluteZ, forKey: .absoluteZ)
        try container.encode(buttons, forKey: .buttons)
    }
}

struct PenEvent: Identifiable, Codable {
    var id: UInt64 = 0
    var identityAtCapture: PenIdentity?
    var eventTypeCode: UInt?
    var mouseSubtypeCode: Int16?
    var screenX: Double?
    var screenY: Double?
    var foregroundBundleID: String?
    let deviceID: Int
    let timestamp: TimeInterval
    let receivedAt: Date
    let source: EventSource
    let typeName: String
    let foregroundApp: String
    let proximity: Bool?
    let info: PenDeviceInfo?
    let sample: PenSample?
}
