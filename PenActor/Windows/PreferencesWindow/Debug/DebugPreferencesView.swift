import SwiftUI
import AppKit

struct DebugPreferencesView: View {
    @ObservedObject var monitor: PenMonitor
    private var device: DeviceState? { monitor.snapshot.selectedDevice }
    private var sample: PenSample? { device?.lastSampleEvent?.sample }
    @State var debugSection = Section.live
    enum Section: String, CaseIterable {
        case live = "实时数值", device = "设备详情", events = "事件记录"

        var title: String {
            switch self {
            case .live: String(localized: "实时数值")
            case .device: String(localized: "设备详情")
            case .events: String(localized: "事件记录")
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "实时调试")).font(.title3.bold())
                Spacer()
                Toggle(String(localized: "置顶"), isOn: $monitor.alwaysOnTop).toggleStyle(.checkbox)
                Button(String(localized: "导出 JSON"), systemImage: "square.and.arrow.up") { monitor.exportLog() }.disabled(monitor.isExporting)
                Button(String(localized: "清空"), systemImage: "trash") { monitor.clear() }
            }
            HStack {
                Picker(String(localized: "设备"), selection: Binding(get: { monitor.snapshot.selectedIdentity }, set: { monitor.selectDevice($0) })) {
                    Text(String(localized: "等待笔输入")).tag(PenIdentity?.none)
                    ForEach(monitor.snapshot.devices) { Text(monitor.deviceDisplayName($0.id)).tag(Optional($0.id)) }
                }.frame(maxWidth: 340)
                Toggle(String(localized: "笔变化时自动切换"), isOn: Binding(get: { monitor.automaticallySwitchDevices }, set: { monitor.setAutomaticSwitching($0) })).toggleStyle(.checkbox)
                Spacer()
            }
            HStack {
                Picker(String(localized: "调试内容"), selection: $debugSection) {
                    ForEach(Section.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 330)
                Spacer()
                Text(device?.status ?? String(localized: "让笔进入感应范围并落笔")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            switch debugSection {
            case .live:
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        samplePanel.frame(maxWidth: .infinity)
                        trendPanel.frame(width: 225)
                    }.fixedSize(horizontal: false, vertical: true)
                    mappingPanel
                    DisclosureGroup(String(localized: "监听状态与读数说明")) {
                        VStack(alignment: .leading, spacing: 5) {
                            status(String(localized: "本地"), installed: monitor.installation.local, received: monitor.receivedLocal)
                            status(String(localized: "全局"), installed: monitor.installation.global, received: monitor.receivedGlobal)
                            Text(String(localized: "NSEvent 读数可能已包含映射结果；tap 诊断记录处理前后压力，两类事件流不逐条对应。"))
                        }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    }.font(.caption)
                }
            case .device:
                hardwarePanel
            case .events:
                eventsPanel.frame(height: 320)
            }
        }.padding(16)
        .alert(String(localized: "导出失败"), isPresented: Binding(get: { monitor.exportError != nil }, set: { if !$0 { monitor.exportError = nil } })) {
            Button(String(localized: "好")) { monitor.exportError = nil }
        } message: { Text(monitor.exportError ?? "") }
    }

    private var mappingPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "压力映射")).font(.headline)
                Spacer()
                Text(String(localized: "修改 \(monitor.mapping.modifiedEventCount) · 缓存 \(monitor.mapping.bufferedEventCount)")).font(.caption).foregroundStyle(.secondary)
            }
            Text(monitor.mapping.localizedStatus).font(.callout)
            if let last = monitor.mapping.diagnostics.last {
                HStack(spacing: 16) {
                    Text(String(localized: "输入 \(number(last.inputPressure)) → 输出 \(number(last.outputPressure))")).monospacedDigit()
                    Text(last.localizedReason).foregroundStyle(.secondary).lineLimit(2)
                }.font(.callout)
                DisclosureGroup(String(localized: "匹配详情")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "目标：\(last.targetBundleID ?? String(localized: "未知应用")) · PID \(last.targetPID)"))
                        Text(String(localized: "设备：\(last.device?.key ?? String(localized: "待识别"))"))
                        Text(String(localized: "配置：\(monitor.profiles.first { $0.id == last.profileID }?.name ?? String(localized: "本笔透传"))"))
                        Text(String(localized: "回调已修改不等于目标应用已确认接收；可导出日志分析。"))
                    }.font(.caption).textSelection(.enabled).padding(.top, 6)
                }.font(.caption)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }

    private func status(_ title: String, installed: Bool, received: Bool) -> some View {
        Text(String(localized: "\(title)：\(installed ? String(localized: "监听器已创建") : String(localized: "未安装")) · \(received ? String(localized: "已收到笔事件") : String(localized: "尚未收到笔事件"))"))
    }

    private var hardwarePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(String(localized: "硬件元数据"), systemImage: "pencil.tip").font(.headline)
            if let device {
                field(String(localized: "身份匹配"), device.id.level.label)
                field(String(localized: "匹配键"), device.id.key)
                field(String(localized: "会话 Device ID"), identifierText(device.lastEvent.deviceID))
                Divider()
                if let info = device.info {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            field(String(localized: "工具类型"), info.localizedToolType)
                            field(String(localized: "Vendor ID"), identifierText(info.vendorID))
                            field(String(localized: "Tablet ID"), identifierText(info.tabletID))
                            field(String(localized: "System tablet"), identifierText(info.systemTabletID))
                            field(String(localized: "Pointing device"), identifierText(info.pointingDeviceID))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 8) {
                            field(String(localized: "厂商工具类型"), identifierText(info.vendorPointingDeviceType))
                            field(String(localized: "序列号"), identifierText(info.serialNumber))
                            field(String(localized: "Unique ID"), identifierText(info.uniqueID))
                            field(String(localized: "Capability mask"), identifierText(info.capabilityMask))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else { Text(String(localized: "硬件信息待获取，请让笔离开再进入感应范围。")).foregroundStyle(.secondary) }
            } else { Text(String(localized: "等待笔输入。连接 Sidecar 或数位板后让笔进入感应范围并落笔。")).foregroundStyle(.secondary) }
            Text(String(localized: "标识为系统 / 驱动报告值，0 可能是占位。同型号归组无法区分缺少唯一标识的多支笔；无事件不代表断开。最多保留 32 个身份。"))
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }

    private var samplePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "应用事件层读数")).font(.headline)
                Spacer()
                if let event = device?.lastSampleEvent {
                    Text(event.source.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(number(sample?.pressure.map(Double.init))).font(.system(size: 24, weight: .medium, design: .monospaced))
                Text(String(localized: "压力 / 1")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(PenCapability.pressure.support(mask: device?.info?.capabilityMask)).font(.caption2).foregroundStyle(.tertiary)
            }
            PressureLevelBar(pressure: sample?.pressure.map(Double.init))
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    metric(String(localized: "倾斜 X"), number(sample?.tiltX), capability: .tiltX)
                    metric(String(localized: "倾斜 Y"), number(sample?.tiltY), capability: .tiltY)
                    metric(String(localized: "笔轴旋转 °"), number(sample.map { Double($0.rotation) }), capability: .rotation)
                }
                GridRow {
                    metric(String(localized: "切向压力"), number(sample.map { Double($0.tangentialPressure) }), capability: .tangentialPressure)
                    metric(String(localized: "绝对 X / Y / Z"), sample.map { "\($0.absoluteX) / \($0.absoluteY) / \($0.absoluteZ)" } ?? String(localized: "未取得"))
                    metric(String(localized: "按钮掩码"), sample.map { identifierText($0.buttons) } ?? String(localized: "未取得"), capability: .buttons)
                }
            }
            if let event = device?.lastSampleEvent {
                Text("\(event.typeName) · \(event.foregroundApp)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                DisclosureGroup(String(localized: "时间与坐标上下文")) {
                    Text(String(localized: "屏幕坐标：\(number(event.screenX)) / \(number(event.screenY))")).font(.caption.monospaced()).textSelection(.enabled)
                    Text(String(localized: "uptime \(event.timestamp.formatted(.number.precision(.fractionLength(4)))) s · 最近 \(event.receivedAt.formatted(date: .omitted, time: .standard)) · 前台应用仅为观察上下文"))
                        .font(.caption.monospaced()).textSelection(.enabled)
                }.font(.caption)
            }
        }.frame(maxHeight: .infinity, alignment: .top).panel()
    }

    private var trendPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "压力趋势")).font(.headline)
                Spacer()
                Text(String(localized: "最近 5 秒")).font(.caption).foregroundStyle(.secondary)
            }
            PressureTrend(events: device?.history ?? [])
                .frame(minHeight: 74, maxHeight: .infinity)
            Text(String(localized: "最多 600 点；停止输入保留曲线，缺失值留空。"))
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxHeight: .infinity).panel()
    }

    private var eventsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = monitor.lastExportURL {
                Text(String(localized: "已导出：\(url.lastPathComponent)")).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(String(localized: "最近事件")).font(.headline)
                Spacer()
                Text(String(localized: "全部设备 · 最近 500 条 · 最新在前")).font(.caption).foregroundStyle(.secondary)
            }
            Table(Array(monitor.snapshot.events.reversed())) {
                TableColumn(String(localized: "时间")) { event in
                    Text(event.receivedAt.formatted(date: .omitted, time: .standard))
                }.width(75)
                TableColumn(String(localized: "来源")) { Text($0.source.label) }.width(65)
                TableColumn(String(localized: "设备")) { Text(String($0.deviceID)) }.width(55)
                TableColumn(String(localized: "类型")) { Text($0.typeName) }
                TableColumn(String(localized: "压力")) { event in Text(number(event.sample?.pressure.map(Double.init))) }.width(70)
                TableColumn(String(localized: "感应")) { event in
                    Text(event.proximity.map { $0 ? String(localized: "进入") : String(localized: "离开") } ?? "—")
                }.width(45)
                TableColumn(String(localized: "前台应用（上下文）")) { Text($0.foregroundApp) }
            }.frame(minHeight: 240, maxHeight: .infinity)
        }.panel()
    }

    private func number(_ value: Double?) -> String {
        value.map { String(format: "%.4f", $0) } ?? String(localized: "未取得")
    }

    private func metric(_ title: String, _ value: String, capability: PenCapability? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                if let capability {
                    Text(capability.support(mask: device?.info?.capabilityMask)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Text(value).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Text(value).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }
    }
}
