import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var monitor: PenMonitor
    private var device: DeviceState? { monitor.snapshot.selectedDevice }
    private var sample: PenSample? { device?.lastSampleEvent?.sample }

    var section: PreferencesSection = .general
    @State private var debugSection = DebugSection.live
    @State private var pencilDetailsExpanded = false
    var onContentHeightChange: ((CGFloat) -> Void)?
    enum DebugSection: String, CaseIterable {
        case live = "实时数值", device = "设备详情", events = "事件记录"
    }

    init(monitor: PenMonitor, section: PreferencesSection = .general, debugSection: DebugSection = .live, pencilDetailsExpanded: Bool = false, onContentHeightChange: ((CGFloat) -> Void)? = nil) {
        self.monitor = monitor; self.section = section
        self.onContentHeightChange = onContentHeightChange
        _debugSection = State(initialValue: debugSection)
        _pencilDetailsExpanded = State(initialValue: pencilDetailsExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch section {
                case .general: GeneralPreferencesView(monitor: monitor).fixedSize(horizontal: false, vertical: true).measurePreferencesHeight("page")
                case .profiles: DeviceProfilesPreferencesView(monitor: monitor)
                case .debug: debugPage.fixedSize(horizontal: false, vertical: true).measurePreferencesHeight("page")
                case .testing: testingPage
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            globalStatusBar.measurePreferencesHeight("footer")
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: section.minimumSize.width, minHeight: section.minimumSize.height)
        .background(WindowConfiguration(alwaysOnTop: monitor.alwaysOnTop))
        .onPreferenceChange(PreferencesHeightKey.self) { values in
            if let page = values["page"], let footer = values["footer"], page > 0 {
                onContentHeightChange?(ceil(page + footer + 1))
            }
        }
    }

    private var globalStatusBar: some View {
        HStack(spacing: 10) {
            Label(monitor.mapping.isRunning ? "映射已启用" : monitor.mapping.isStarting ? "映射正在启动" : "映射已暂停",
                  systemImage: monitor.mapping.isRunning ? "arrow.triangle.2.circlepath" : "pause.circle")
            Divider().frame(height: 12)
            Button("暂停全部映射", systemImage: "pause.fill") { monitor.pauseMapping() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!monitor.mapping.isRunning && !monitor.mapping.isStarting && monitor.enabledProfileIDs.isEmpty)
                .help("暂停所有设备的压力映射，不停止输入服务（⌘⇧R）")
            Spacer(minLength: 20)
            Label(monitor.isRunning ? "输入服务运行中" : "输入服务已停止", systemImage: monitor.isRunning ? "waveform" : "pause.circle")
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color(nsColor: .underPageBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("全局运行状态与控制")
    }

    private var debugPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("实时调试").font(.title3.bold())
                Spacer()
                Toggle("置顶", isOn: $monitor.alwaysOnTop).toggleStyle(.checkbox)
                Button("导出 JSON", systemImage: "square.and.arrow.up") { monitor.exportLog() }.disabled(monitor.isExporting)
                Button("清空", systemImage: "trash") { monitor.clear() }
            }
            HStack {
                Picker("设备", selection: Binding(get: { monitor.snapshot.selectedIdentity }, set: { monitor.selectDevice($0) })) {
                    Text("等待笔输入").tag(PenIdentity?.none)
                    ForEach(monitor.snapshot.devices) { Text(monitor.deviceDisplayName($0.id)).tag(Optional($0.id)) }
                }.frame(maxWidth: 340)
                Toggle("笔变化时自动切换", isOn: Binding(get: { monitor.automaticallySwitchDevices }, set: { monitor.setAutomaticSwitching($0) })).toggleStyle(.checkbox)
                Spacer()
            }
            HStack {
                Picker("调试内容", selection: $debugSection) {
                    ForEach(DebugSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 330)
                Spacer()
                Text(device?.status ?? "让笔进入感应范围并落笔").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            switch debugSection {
            case .live:
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        samplePanel.frame(maxWidth: .infinity)
                        trendPanel.frame(width: 225)
                    }.fixedSize(horizontal: false, vertical: true)
                    mappingPanel
                    DisclosureGroup("监听状态与读数说明") {
                        VStack(alignment: .leading, spacing: 5) {
                            status("本地", installed: monitor.installation.local, received: monitor.receivedLocal)
                            status("全局", installed: monitor.installation.global, received: monitor.receivedGlobal)
                            Text("NSEvent 读数可能已包含映射结果；tap 诊断记录处理前后压力，两类事件流不逐条对应。")
                        }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    }.font(.caption)
                }
            case .device:
                hardwarePanel
            case .events:
                eventsPanel.frame(height: 320)
            }
        }.padding(16)
        .alert("导出失败", isPresented: Binding(get: { monitor.exportError != nil }, set: { if !$0 { monitor.exportError = nil } })) {
            Button("好") { monitor.exportError = nil }
        } message: { Text(monitor.exportError ?? "") }
    }

    private var mappingPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("压力映射").font(.headline)
                Spacer()
                Text("修改 \(monitor.mapping.modifiedEventCount) · 缓存 \(monitor.mapping.bufferedEventCount)").font(.caption).foregroundStyle(.secondary)
            }
            Text(monitor.mapping.status).font(.callout)
            if let last = monitor.mapping.diagnostics.last {
                HStack(spacing: 16) {
                    Text("输入 \(number(last.inputPressure)) → 输出 \(number(last.outputPressure))").monospacedDigit()
                    Text(last.reason).foregroundStyle(.secondary).lineLimit(2)
                }.font(.callout)
                if let reason = last.smoothingBypassReason {
                    Text(reason).font(.caption).foregroundStyle(.orange)
                }
                DisclosureGroup("匹配详情") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("目标：\(last.targetBundleID ?? "未知应用") · PID \(last.targetPID)")
                        Text("设备：\(last.device?.key ?? "待识别")")
                        Text("配置：\(monitor.profiles.first { $0.id == last.profileID }?.name ?? "本笔透传")")
                        Text("回调已修改不等于目标应用已确认接收；可导出日志分析。")
                    }.font(.caption).textSelection(.enabled).padding(.top, 6)
                }.font(.caption)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }

    private var testingPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("笔迹测试").font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
            testPanel.frame(maxHeight: .infinity)
            pencilInteractionPanel.fixedSize(horizontal: false, vertical: true)
        }.padding(16)
            .modifier(PencilInteractionObserver(monitor: monitor))
            .onDisappear { monitor.interruptPencilInteraction() }
    }

    private func status(_ title: String, installed: Bool, received: Bool) -> some View {
        Text("\(title)：\(installed ? "监听器已创建" : "未安装") · \(received ? "已收到笔事件" : "尚未收到笔事件")")
    }

    private var pencilInteractionPanel: some View {
        let interactions = monitor.pencilInteractions
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 24) {
                Label("Pencil 手势", systemImage: "hand.tap").font(.headline)
                Text("双击 \(interactions.doubleTapCount) 次").monospacedDigit()
                Text("挤压 \(interactions.squeezeCount) 次 · \(interactions.squeezeStatus.rawValue)").monospacedDigit()
            }.font(.callout)
            DisclosureGroup("手势说明与来源", isExpanded: $pencilDetailsExpanded) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("双击最近：\(interactionTime(interactions.lastDoubleTapAt)) · \(interactions.doubleTapPaired ? "changeMode + SwiftUI（已去重）" : interactions.lastDoubleTapSource?.rawValue ?? "等待回调")")
                    Text("挤压最近：\(interactionTime(interactions.lastSqueezeAt)) · 完成 \(interactions.squeezeCompletedCount) · 失败 / 取消 \(interactions.squeezeFailedCount) · SwiftUI")
                    Text("窗口移到 iPad 并激活后测试。双击需在显示器设置中启用；挤压需 Pencil Pro。仅记录本窗口手势，不归属某支笔，也不代表可监听其他应用手势。")
                    if #unavailable(macOS 14.5) { Text("SwiftUI 双击 / 挤压需 macOS 14.5 或更新；当前仅接入 changeMode 双击。") }
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 6)
            }.font(.caption)
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }

    private func interactionTime(_ date: Date?) -> String {
        date?.formatted(.dateTime.hour().minute().second().secondFraction(.fractional(3))) ?? "—"
    }

    private var hardwarePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("硬件元数据", systemImage: "pencil.tip").font(.headline)
            if let device {
                field("身份匹配", device.id.level.label)
                field("匹配键", device.id.key)
                field("会话 Device ID", identifierText(device.lastEvent.deviceID))
                Divider()
                if let info = device.info {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            field("工具类型", info.toolType)
                            field("Vendor ID", identifierText(info.vendorID))
                            field("Tablet ID", identifierText(info.tabletID))
                            field("System tablet", identifierText(info.systemTabletID))
                            field("Pointing device", identifierText(info.pointingDeviceID))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 8) {
                            field("厂商工具类型", identifierText(info.vendorPointingDeviceType))
                            field("序列号", identifierText(info.serialNumber))
                            field("Unique ID", identifierText(info.uniqueID))
                            field("Capability mask", identifierText(info.capabilityMask))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else { Text("硬件信息待获取，请让笔离开再进入感应范围。").foregroundStyle(.secondary) }
            } else { Text("等待笔输入。连接 Sidecar 或数位板后让笔进入感应范围并落笔。").foregroundStyle(.secondary) }
            Text("标识为系统 / 驱动报告值，0 可能是占位。同型号归组无法区分缺少唯一标识的多支笔；无事件不代表断开。最多保留 32 个身份。")
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }

    private var samplePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("应用事件层读数").font(.headline)
                Spacer()
                if let event = device?.lastSampleEvent {
                    Text(event.source.rawValue).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(number(sample?.pressure.map(Double.init))).font(.system(size: 24, weight: .medium, design: .monospaced))
                Text("压力 / 1").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(PenCapability.pressure.support(mask: device?.info?.capabilityMask)).font(.caption2).foregroundStyle(.tertiary)
            }
            PressureLevelBar(pressure: sample?.pressure.map(Double.init))
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    metric("倾斜 X", number(sample?.tiltX), capability: .tiltX)
                    metric("倾斜 Y", number(sample?.tiltY), capability: .tiltY)
                    metric("笔轴旋转 °", number(sample.map { Double($0.rotation) }), capability: .rotation)
                }
                GridRow {
                    metric("切向压力", number(sample.map { Double($0.tangentialPressure) }), capability: .tangentialPressure)
                    metric("绝对 X / Y / Z", sample.map { "\($0.absoluteX) / \($0.absoluteY) / \($0.absoluteZ)" } ?? "未取得")
                    metric("按钮掩码", sample.map { identifierText($0.buttons) } ?? "未取得", capability: .buttons)
                }
            }
            if let event = device?.lastSampleEvent {
                Text("\(event.typeName) · \(event.foregroundApp)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                DisclosureGroup("时间与坐标上下文") {
                    Text("屏幕坐标：\(number(event.screenX)) / \(number(event.screenY))").font(.caption.monospaced()).textSelection(.enabled)
                    Text("uptime \(event.timestamp.formatted(.number.precision(.fractionLength(4)))) s · 最近 \(event.receivedAt.formatted(date: .omitted, time: .standard)) · 前台应用仅为观察上下文")
                        .font(.caption.monospaced()).textSelection(.enabled)
                }.font(.caption)
            }
        }.frame(maxHeight: .infinity, alignment: .top).panel()
    }

    private var trendPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("压力趋势").font(.headline)
                Spacer()
                Text("最近 5 秒").font(.caption).foregroundStyle(.secondary)
            }
            PressureTrend(events: device?.history ?? [])
                .frame(minHeight: 74, maxHeight: .infinity)
            Text("最多 600 点；停止输入保留曲线，缺失值留空。")
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxHeight: .infinity).panel()
    }

    private var testPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("笔输入测试区").font(.headline)
                Button("清空笔迹与记录") { monitor.clear() }
                Spacer()
                Text("线宽随系统压力变化 · 仅接受笔事件").font(.caption).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
            TestPad(isRunning: monitor.isRunning, clearGeneration: monitor.clearGeneration)
                .frame(minHeight: 100, maxHeight: .infinity).layoutPriority(-1)
            Text("使用 Sidecar 时请把此窗口移至 iPad。此区域是输入验证工具；不应用平滑或压力曲线。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.panel()
    }

    private var eventsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = monitor.lastExportURL {
                Text("已导出：\(url.lastPathComponent)").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("最近事件").font(.headline)
                Spacer()
                Text("全部设备 · 最近 500 条 · 最新在前").font(.caption).foregroundStyle(.secondary)
            }
            Table(Array(monitor.snapshot.events.reversed())) {
                TableColumn("时间") { event in
                    Text(event.receivedAt.formatted(date: .omitted, time: .standard))
                }.width(75)
                TableColumn("来源") { Text($0.source.rawValue) }.width(65)
                TableColumn("设备") { Text(String($0.deviceID)) }.width(55)
                TableColumn("类型") { Text($0.typeName) }
                TableColumn("压力") { event in Text(number(event.sample?.pressure.map(Double.init))) }.width(70)
                TableColumn("感应") { event in
                    Text(event.proximity.map { $0 ? "进入" : "离开" } ?? "—")
                }.width(45)
                TableColumn("前台应用（上下文）") { Text($0.foregroundApp) }
            }.frame(minHeight: 240, maxHeight: .infinity)
        }.panel()
    }

    private func number(_ value: Double?) -> String {
        value.map { String(format: "%.4f", $0) } ?? "未取得"
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

private struct PencilInteractionObserver: ViewModifier {
    let monitor: PenMonitor

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14.5, *) {
            content
                .onPencilDoubleTap { _ in monitor.recordPencilDoubleTap(source: .swiftUI) }
                .onPencilSqueeze { phase in
                    switch phase {
                    case .active: monitor.recordPencilSqueeze(.active)
                    case .ended: monitor.recordPencilSqueeze(.ended)
                    case .failed: monitor.recordPencilSqueeze(.failed)
                    }
                }
        } else {
            content
        }
    }
}

private extension View {
    func panel() -> some View {
        padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.quaternary, lineWidth: 1))
    }
}

private struct PressureTrend: View {
    let events: [PenEvent]

    var body: some View {
        Canvas { context, size in
            let end = events.last?.timestamp ?? 0
            let start = end - 5
            var grid = Path()
            for fraction in [0.0, 0.5, 1.0] {
                let y = fraction * size.height
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(.secondary.opacity(0.2)), lineWidth: 1)
            var path = Path()
            var previousTime: TimeInterval?
            for event in events where event.timestamp >= start {
                guard let pressure = event.sample?.pressure else { previousTime = nil; continue }
                let point = CGPoint(x: (event.timestamp - start) / 5 * size.width,
                                    y: (1 - Double(max(0, min(1, pressure)))) * size.height)
                if let previousTime, event.timestamp - previousTime < 0.25 { path.addLine(to: point) }
                else { path.move(to: point) }
                previousTime = event.timestamp
            }
            context.stroke(path, with: .color(.accentColor), lineWidth: 2)
        }
    }
}

/// A live meter, not an animated task-progress indicator. Canvas draws the latest value directly.
struct PressureLevelBar: View {
    let pressure: Double?
    private var fraction: Double {
        guard let pressure, pressure.isFinite else { return 0 }
        return min(1, max(0, pressure))
    }
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let track = Path(roundedRect: bounds, cornerRadius: size.height / 2)
            context.fill(track, with: .color(.secondary.opacity(0.12)))
            context.stroke(track, with: .color(.secondary.opacity(0.2)), lineWidth: 0.5)
            let width = size.width * fraction
            if width > 0 {
                let fill = Path(roundedRect: CGRect(x: 0, y: 0, width: width, height: size.height), cornerRadius: min(size.height / 2, width / 2))
                context.fill(fill, with: .color(.accentColor))
            }
        }
        .frame(height: 8)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("压力")
        .accessibilityValue(pressure?.isFinite == true ? fraction.formatted(.percent.precision(.fractionLength(1))) : "未取得")
    }
}

private struct WindowConfiguration: NSViewRepresentable {
    let alwaysOnTop: Bool
    func makeNSView(context: Context) -> WindowLevelView { WindowLevelView() }
    func updateNSView(_ view: WindowLevelView, context: Context) {
        view.floating = alwaysOnTop
        view.apply()
    }
}

private final class WindowLevelView: NSView {
    var floating = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }
    func apply() {
        window?.level = floating ? .floating : .normal
        window?.acceptsMouseMovedEvents = true
    }
}

// Measure intrinsic page content, independently of the available window height.
private struct PreferencesHeightKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
private extension View {
    func measurePreferencesHeight(_ part: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: PreferencesHeightKey.self, value: [part: proxy.size.height])
        })
    }
}
