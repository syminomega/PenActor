import Foundation

/// Versioned deterministic keys; never use Swift's randomized hashValue for persistence.
struct PenIdentity: Hashable, Codable, Sendable {
    enum MatchLevel: String, Codable, Sendable {
        case uniqueTool, serialNumber, model, session

        var label: String {
            switch self {
            case .uniqueTool: String(localized: "Unique pen ID")
            case .serialNumber: String(localized: "Pen serial number")
            case .model: String(localized: "Model group (cannot distinguish identical devices)")
            case .session: String(localized: "Temporary session (awaiting hardware metadata)")
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
