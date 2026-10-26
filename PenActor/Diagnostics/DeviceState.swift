import Foundation

struct DeviceState: Identifiable {
    let id: PenIdentity
    var info: PenDeviceInfo?
    var proximity: Bool?
    var lastEvent: PenEvent
    var lastSampleEvent: PenEvent?
    var history: [PenEvent] = []

    var title: String {
        guard let info else { return String(localized: "待识别工具 · 会话 \(lastEvent.deviceID)") }
        let model = "\(String(info.vendorID, radix: 16).uppercased()) / \(String(info.tabletID, radix: 16).uppercased())"
        switch id.level {
        case .uniqueTool: return "\(info.localizedToolType) · \(model) · \(String(info.uniqueID, radix: 16).uppercased())"
        case .serialNumber: return "\(info.localizedToolType) · \(model) · SN \(info.serialNumber)"
        case .model: return String(localized: "\(info.localizedToolType) · \(model)（型号）")
        case .session: return String(localized: "\(info.localizedToolType) · 会话 \(lastEvent.deviceID)")
        }
    }

    var status: String {
        switch proximity {
        case true: String(localized: "在感应范围内（最近报告）")
        case false: String(localized: "已离开感应范围 · 显示历史读数")
        case nil: String(localized: "已收到笔事件 · 感应状态未知")
        }
    }
}
