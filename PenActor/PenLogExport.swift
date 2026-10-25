import Foundation

/// An immutable snapshot of the retained event buffer, ordered oldest first.
struct PenLogDocument: Codable {
    struct Device: Codable {
        let identity: PenIdentity
        let currentSessionDeviceID: Int
        let info: PenDeviceInfo?
        let proximity: Bool?
    }

    struct PencilGestures: Codable {
        let doubleTapCount: Int
        let lastDoubleTapAt: Date?
        let lastDoubleTapSource: PencilDoubleTapSource?
        let doubleTapPaired: Bool
        let squeezeCount: Int
        let squeezeCompletedCount: Int
        let squeezeFailedCount: Int
        let squeezeStatus: PencilSqueezeStatus
        let lastSqueezeAt: Date?
    }

    let profiles: [PressureProfile]
    let mapping: MappingSnapshot
    let touchBlocking: TouchRightClickSnapshot?
    let schemaVersion: Int
    let exportedAt: Date
    let appVersion: String
    let appBuild: String
    let operatingSystem: String
    let isMonitoring: Bool
    let totalObservedEvents: UInt64
    let retainedEventCount: Int
    let discardedEventCount: UInt64
    let eventCapacity: Int
    let selectedIdentity: PenIdentity?
    let devices: [Device]
    let events: [PenEvent]
    let pencilGestures: PencilGestures
    let notes: [String]

    init(store: PenStore, interactions: PencilInteractionStats, isMonitoring: Bool,
         exportedAt: Date = Date(), bundle: Bundle = .main, profiles: [PressureProfile] = [], mapping: MappingSnapshot = MappingSnapshot(), touchBlocking: TouchRightClickSnapshot? = nil) {
        schemaVersion = 3
        self.profiles = profiles
        self.mapping = mapping
        self.touchBlocking = touchBlocking
        self.exportedAt = exportedAt
        appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        appBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        operatingSystem = ProcessInfo.processInfo.operatingSystemVersionString
        self.isMonitoring = isMonitoring
        totalObservedEvents = store.totalEvents
        retainedEventCount = store.events.count
        discardedEventCount = store.totalEvents - UInt64(store.events.count)
        eventCapacity = PenStore.eventLimit
        selectedIdentity = store.selectedIdentity
        devices = store.devices.map {
            Device(identity: $0.id, currentSessionDeviceID: $0.lastEvent.deviceID,
                   info: $0.info, proximity: $0.proximity)
        }
        events = store.events
        pencilGestures = PencilGestures(
            doubleTapCount: interactions.doubleTapCount, lastDoubleTapAt: interactions.lastDoubleTapAt,
            lastDoubleTapSource: interactions.lastDoubleTapSource, doubleTapPaired: interactions.doubleTapPaired,
            squeezeCount: interactions.squeezeCount, squeezeCompletedCount: interactions.squeezeCompletedCount,
            squeezeFailedCount: interactions.squeezeFailedCount, squeezeStatus: interactions.squeezeStatus,
            lastSqueezeAt: interactions.lastSqueezeAt
        )
        notes = [
            "mapping.coordinateProbes 最多保留 16 份命中设备/应用的笔事件序列化样本（各设备每种事件形式一份），仅供进程内复现；eventData 是 Base64 Quartz 数据，包含坐标与进程/设备信息，不包含键盘事件。只在导出时写入文件。",
            "mapping.diagnostics.eventType、inputPosition/outputPosition 与 smoothing 为 tap 层轨迹诊断；位置单位为全局屏幕点，inputTablet/outputTablet 保留数位板单位。平滑不增加采样点。",
            "profiles.applicationRules 定义当前配置中的应用继承、覆盖或不映射；mapping.defaults.devices 保存每台设备默认。旧全局字段仅用于迁移，不参与新配置解析。",
            "mapping.diagnostics.taper 记录曲线输出、入锋/出锋系数、累计屏幕距离和经过时间；出锋缓存并延迟输出，delivery 标识直接、延迟或提前排空。诊断在准备输出时记录，不表示目标应用已确认接收。",
            "mapping.diagnostics 来自主动作业 tap，记录修改前后压力；与 NSEvent events 不做一一关联。NSEvent 可能已包含映射结果。",
            "events 按采集顺序排列（最旧在前），包含全部设备最近保留的事件，不限于当前选择。",
            "timestamp 是 NSEvent 系统 uptime 秒，未按界面精度舍入；receivedAt 是本机接收时间（UTC ISO 8601，毫秒）。",
            "sample.pressure 为 null 表示该事件未取得有效压力，不等于零；proximity 事件没有 sample。",
            "screenX/screenY 为 CGEvent 全局屏幕点坐标；sample.absoluteX/Y/Z 为驱动上报的数位板坐标。",
            "foregroundApp/foregroundBundleID 仅是回调时的前台应用上下文，不保证是事件接收应用。",
            "identityAtCapture 是当时解析的身份，可能尚为临时 session；后续 proximity 可补充硬件信息。",
            "压力来自系统事件，可能已经过驱动或 Sidecar 处理，不是物理力度或未经处理的硬件原始数据。",
            "本文件是导出按钮按下时的快照，不是持续录制；discardedEventCount > 0 表示更早事件已被缓存淘汰。",
            "Pencil 手势仅导出累计摘要，不属于逐条 tablet 事件，也不关联到某一支笔。"
        ]
    }

    func jsonData() throws -> Data {
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(style))
        }
        return try encoder.encode(self)
    }
}
