import Foundation

struct DeviceState: Identifiable {
    let id: PenIdentity
    var info: PenDeviceInfo?
    var proximity: Bool?
    var lastEvent: PenEvent
    var lastSampleEvent: PenEvent?
    var history: [PenEvent] = []

    var title: String {
        guard let info else { return String(localized: "Unidentified tool · Session \(lastEvent.deviceID)") }
        let model = "\(String(info.vendorID, radix: 16).uppercased()) / \(String(info.tabletID, radix: 16).uppercased())"
        switch id.level {
        case .uniqueTool: return "\(info.localizedToolType) · \(model) · \(String(info.uniqueID, radix: 16).uppercased())"
        case .serialNumber: return "\(info.localizedToolType) · \(model) · SN \(info.serialNumber)"
        case .model: return String(localized: "\(info.localizedToolType) · \(model) (model)")
        case .session: return String(localized: "\(info.localizedToolType) · Session \(lastEvent.deviceID)")
        }
    }

    var status: String {
        switch proximity {
        case true: String(localized: "In range (last reported)")
        case false: String(localized: "Out of range · Showing previous readings")
        case nil: String(localized: "Pen events received · Range unknown")
        }
    }
}
