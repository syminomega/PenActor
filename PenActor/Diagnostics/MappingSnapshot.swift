import Foundation

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


extension MappingSnapshot {
    var localizedStatus: String {
        // Match legacy diagnostic values without making them localization keys.
        switch status {
        case "映射已暂停": String(localized: "Mapping paused")
        case "正在创建事件 tap…": String(localized: "Creating event tap…")
        case "无法创建事件 tap，请检查辅助功能权限": String(localized: "Could not create the event tap. Check Accessibility access.")
        case "正在映射（等待匹配事件）": String(localized: "Mapping active (waiting for matching input)")
        case "事件线程已结束；映射已停止，请手动重新启用": String(localized: "The event thread ended. Mapping stopped; enable it again manually.")
        case "系统停用了事件 tap；映射已停止，请手动重新启用": String(localized: "The system disabled the event tap. Mapping stopped; enable it again manually.")
        default: status
        }
    }
}

extension MappingDiagnostic {
    var localizedReason: String {
        // Match legacy diagnostic values without making them localization keys.
        switch reason {
        case "已应用曲线": String(localized: "Curve applied")
        case "等待 proximity 识别设备": String(localized: "Waiting for proximity metadata to identify the device")
        case "目标应用未知": String(localized: "Target app unknown")
        case "设备或应用未启用配置 / 本笔透传": String(localized: "No enabled profile for this device or app / Passing through this stroke")
        case "暂停 / 禁用：缓存恢复原输入": String(localized: "Paused / Disabled: queued input restored")
        default: reason
        }
    }
}
