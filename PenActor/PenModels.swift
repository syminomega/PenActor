import AppKit

enum PencilDoubleTapSource: String {
    case appKit = "NSEvent.changeMode"
    case swiftUI = "SwiftUI"
}

enum PencilSqueezeStatus: String {
    case waiting = "尚未收到"
    case active = "正在挤压"
    case ended = "挤压已结束"
    case failed = "失败 / 取消"
    case interrupted = "监听停止 / 窗口失活，已中断"
}

struct PencilInteractionStats {
    private(set) var doubleTapCount = 0
    private(set) var lastDoubleTapAt: Date?
    private(set) var lastDoubleTapSource: PencilDoubleTapSource?
    private(set) var doubleTapPaired = false
    private var lastDoubleTapUptime: TimeInterval?
    private(set) var squeezeCount = 0
    private(set) var squeezeCompletedCount = 0
    private(set) var squeezeFailedCount = 0
    private(set) var squeezeStatus: PencilSqueezeStatus = .waiting
    private(set) var lastSqueezeAt: Date?

    mutating func doubleTap(source: PencilDoubleTapSource, uptime: TimeInterval, date: Date) {
        // SwiftUI and AppKit can report the same double tap. Pair one callback
        // from each source within 150 ms; never debounce repeated same-source taps.
        if let previous = lastDoubleTapUptime, source != lastDoubleTapSource,
           !doubleTapPaired, uptime >= previous, uptime - previous <= 0.15 {
            doubleTapPaired = true
            return
        }
        doubleTapCount += 1
        lastDoubleTapAt = date
        lastDoubleTapSource = source
        lastDoubleTapUptime = uptime
        doubleTapPaired = false
    }

    mutating func squeeze(_ status: PencilSqueezeStatus, date: Date) {
        guard status == .active || status == .ended || status == .failed else { return }
        // Ignore a late terminal callback from the gesture interrupted by stop/focus loss.
        if squeezeStatus == .interrupted && status != .active { return }
        let wasActive = squeezeStatus == .active
        if status == .active {
            if !wasActive { squeezeCount += 1 }
        } else {
            // A framework may deliver only the terminal callback.
            if !wasActive { squeezeCount += 1 }
            if status == .ended { squeezeCompletedCount += 1 }
            else { squeezeFailedCount += 1 }
        }
        squeezeStatus = status
        lastSqueezeAt = date
    }

    mutating func interrupt(date: Date) {
        lastDoubleTapUptime = nil
        if squeezeStatus == .active {
            squeezeStatus = .interrupted
            lastSqueezeAt = date
        }
    }
}

enum EventSource: String, Sendable {
    case local = "本应用"
    case global = "其他应用"
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

struct PenDeviceInfo: Equatable {
    let vendorID: Int
    let tabletID: Int
    let pointingDeviceID: Int
    let systemTabletID: Int
    let vendorPointingDeviceType: Int
    let serialNumber: Int
    let uniqueID: UInt64
    let capabilityMask: Int
    let toolType: String
}

enum PenCapability: Int {
    // Public SDK: IOKit/hidsystem/IOLLEvent.h NX_TABLET_CAPABILITY_*MASK.
    case absoluteX = 0x0002, absoluteY = 0x0004, buttons = 0x0040
    case tiltX = 0x0080, tiltY = 0x0100, absoluteZ = 0x0200
    case pressure = 0x0400, tangentialPressure = 0x0800, rotation = 0x2000

    func support(mask: Int?) -> String {
        guard let mask, mask != 0 else { return "支持情况未知" }
        return mask & rawValue != 0 ? "驱动声明支持" : "驱动未声明支持"
    }
}

struct PenSample: Equatable {
    let pressure: Float?
    let tiltX: Double
    let tiltY: Double
    let rotation: Float
    let tangentialPressure: Float
    let absoluteX: Int
    let absoluteY: Int
    let absoluteZ: Int
    let buttons: UInt
}

struct PenEvent: Identifiable {
    var id: UInt64 = 0
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

/// Versioned deterministic keys; never use Swift's randomized hashValue for persistence.
struct PenIdentity: Hashable {
    enum MatchLevel: String {
        case uniqueTool, serialNumber, model, session

        var label: String {
            switch self {
            case .uniqueTool: "笔唯一标识"
            case .serialNumber: "笔序列号"
            case .model: "型号归组（无法区分同型号实体）"
            case .session: "临时会话（等待硬件信息）"
            }
        }
    }

    let key: String
    let level: MatchLevel

    static func session(_ deviceID: Int) -> Self {
        Self(key: "session:\(deviceID)", level: .session)
    }

    static func resolve(info: PenDeviceInfo, deviceID: Int) -> Self {
        let tool: String
        switch info.toolType {
        case "笔": tool = "pen"
        case "橡皮擦": tool = "eraser"
        case "数位板光标": tool = "cursor"
        default: tool = "unknown"
        }
        let vendor = String(info.vendorID, radix: 16)
        if info.vendorID > 0 && info.uniqueID != 0 && info.uniqueID != UInt64.max {
            return Self(key: "v1:tool:\(vendor):\(String(info.uniqueID, radix: 16)):\(tool)", level: .uniqueTool)
        }
        if info.vendorID > 0 && info.serialNumber > 0 {
            return Self(key: "v1:serial:\(vendor):\(String(info.serialNumber, radix: 16)):\(info.vendorPointingDeviceType):\(tool)", level: .serialNumber)
        }
        if info.vendorID > 0 && info.tabletID > 0 {
            return Self(key: "v1:model:\(vendor):\(String(info.tabletID, radix: 16)):\(info.vendorPointingDeviceType):\(tool)", level: .model)
        }
        return .session(deviceID)
    }
}

struct DeviceState: Identifiable {
    let id: PenIdentity
    var info: PenDeviceInfo?
    var proximity: Bool?
    var lastEvent: PenEvent
    var lastSampleEvent: PenEvent?
    var history: [PenEvent] = []

    var title: String {
        guard let info else { return "待识别工具 · 会话 \(lastEvent.deviceID)" }
        let model = "\(String(info.vendorID, radix: 16).uppercased()) / \(String(info.tabletID, radix: 16).uppercased())"
        switch id.level {
        case .uniqueTool: return "\(info.toolType) · \(model) · \(String(info.uniqueID, radix: 16).uppercased())"
        case .serialNumber: return "\(info.toolType) · \(model) · SN \(info.serialNumber)"
        case .model: return "\(info.toolType) · \(model)（型号）"
        case .session: return "\(info.toolType) · 会话 \(lastEvent.deviceID)"
        }
    }

    var status: String {
        switch proximity {
        case true: "在感应范围内（最近报告）"
        case false: "已离开感应范围 · 显示历史读数"
        case nil: "已收到笔事件 · 感应状态未知"
        }
    }
}

struct PenStore {
    static let eventLimit = 500
    static let historyLimit = 600
    static let deviceLimit = 32
    static let sessionLimit = 128
    private(set) var devices: [DeviceState] = []
    private(set) var events: [PenEvent] = []
    private(set) var totalEvents: UInt64 = 0
    var selectedIdentity: PenIdentity?
    private(set) var lastActiveIdentity: PenIdentity?
    var automaticallySwitchDevices = true
    private var sessions: [Int: PenIdentity] = [:]
    private var sessionOrder: [Int] = []

    var selectedDevice: DeviceState? { devices.first { $0.id == selectedIdentity } }

    mutating func ingest(_ incoming: PenEvent) {
        totalEvents += 1
        var event = incoming
        event.id = totalEvents
        let previousIdentity = sessions[event.deviceID]
        let reportedIdentity = event.info.map { PenIdentity.resolve(info: $0, deviceID: event.deviceID) }
        // An incomplete departure packet must not demote an already identified device.
        let identity: PenIdentity
        if let previousIdentity, event.proximity == false {
            identity = previousIdentity
        } else if let reportedIdentity, reportedIdentity.level != .session {
            identity = reportedIdentity
        } else {
            identity = previousIdentity ?? .session(event.deviceID)
        }

        // Promote a provisional row when proximity metadata arrives. If the stable row
        // already exists, merge into it instead of leaving a duplicate row behind.
        if let previousIdentity, previousIdentity != identity, previousIdentity.level == .session,
           let provisional = devices.first(where: { $0.id == previousIdentity }) {
            if let target = devices.firstIndex(where: { $0.id == identity }) {
                if provisional.lastSampleEvent != nil {
                    devices[target].lastSampleEvent = provisional.lastSampleEvent
                    devices[target].history += provisional.history
                    devices[target].history.sort { $0.id < $1.id }
                    devices[target].history = Array(devices[target].history.suffix(Self.historyLimit))
                }
                devices[target].lastEvent = provisional.lastEvent
            } else {
                devices.append(DeviceState(id: identity, lastEvent: provisional.lastEvent,
                                           lastSampleEvent: provisional.lastSampleEvent, history: provisional.history))
            }
            devices.removeAll { $0.id == previousIdentity }
            if selectedIdentity == previousIdentity { selectedIdentity = identity }
            if lastActiveIdentity == previousIdentity { lastActiveIdentity = identity }
        } else if let previousIdentity, previousIdentity != identity,
                  let old = devices.firstIndex(where: { $0.id == previousIdentity }),
                  devices[old].lastEvent.deviceID == event.deviceID {
            // A recycled session ID now refers to a different pen.
            devices[old].proximity = false
        }
        rememberSession(event.deviceID, identity: identity)

        if !devices.contains(where: { $0.id == identity }) {
            if devices.count >= Self.deviceLimit {
                let removed = devices.removeFirst()
                let obsolete = Set(sessions.filter { $0.value == removed.id }.map(\.key))
                sessions = sessions.filter { !obsolete.contains($0.key) }
                sessionOrder.removeAll { obsolete.contains($0) }
                if selectedIdentity == removed.id { selectedIdentity = nil }
                if lastActiveIdentity == removed.id { lastActiveIdentity = nil }
            }
            devices.append(DeviceState(id: identity, lastEvent: event))
        }
        guard let index = devices.firstIndex(where: { $0.id == identity }) else { return }
        // Ignore late departures from a previous connection after this device reconnects.
        let retiredSession = event.proximity == false && devices[index].lastEvent.deviceID != event.deviceID
        let outOfOrder = event.timestamp < devices[index].lastEvent.timestamp
        if !retiredSession && !outOfOrder {
            if let info = event.info, reportedIdentity == identity { devices[index].info = info }
            if event.proximity == true, let previousSample = devices[index].lastSampleEvent,
               previousSample.deviceID != event.deviceID {
                devices[index].lastSampleEvent = nil
            }
            if let proximity = event.proximity { devices[index].proximity = proximity }
            devices[index].lastEvent = event
            if event.sample != nil {
                devices[index].lastSampleEvent = event
                devices[index].history.append(event)
                if devices[index].history.count > Self.historyLimit {
                    devices[index].history.removeFirst(devices[index].history.count - Self.historyLimit)
                }
            }
            // Departures never steal selection. Repeated packets from the same active
            // pen do not undo a manual selection until the active pen actually changes.
            if event.proximity == true || event.sample != nil {
                if automaticallySwitchDevices && lastActiveIdentity != identity { selectedIdentity = identity }
                lastActiveIdentity = identity
            }
        }
        if selectedIdentity == nil { selectedIdentity = identity }
        events.append(event)
        if events.count > Self.eventLimit { events.removeFirst(events.count - Self.eventLimit) }
    }

    mutating func setAutomaticSwitching(_ enabled: Bool) {
        automaticallySwitchDevices = enabled
        if enabled, let lastActiveIdentity { selectedIdentity = lastActiveIdentity }
    }

    private mutating func rememberSession(_ deviceID: Int, identity: PenIdentity) {
        if sessions[deviceID] == nil { sessionOrder.append(deviceID) }
        sessions[deviceID] = identity
        while sessionOrder.count > Self.sessionLimit {
            sessions.removeValue(forKey: sessionOrder.removeFirst())
        }
    }

    mutating func clear() {
        let automatic = automaticallySwitchDevices
        self = PenStore()
        automaticallySwitchDevices = automatic
    }
}

func identifierText<T: BinaryInteger>(_ value: T) -> String {
    "\(value) / 0x\(String(value, radix: 16).uppercased())"
}
