import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var monitor: PenMonitor
    private var device: DeviceState? { monitor.snapshot.selectedDevice }
    private var sample: PenSample? { device?.lastSampleEvent?.sample }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    permissionPanel
                    pencilInteractionPanel
                    HStack(alignment: .top, spacing: 16) {
                        hardwarePanel.frame(minWidth: 300, maxWidth: 360)
                        VStack(alignment: .leading, spacing: 16) {
                            samplePanel
                            trendPanel
                        }.frame(maxWidth: .infinity)
                    }
                    testPanel
                    eventsPanel
                }.padding(20)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 960, minHeight: 740)
        .background(WindowConfiguration(alwaysOnTop: monitor.alwaysOnTop))
        .modifier(PencilInteractionObserver(monitor: monitor))
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            monitor.refreshPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            monitor.interruptPencilInteraction()
        }
        .alert("导出失败", isPresented: Binding(
            get: { monitor.exportError != nil },
            set: { if !$0 { monitor.exportError = nil } }
        )) {
            Button("好") { monitor.exportError = nil }
        } message: { Text(monitor.exportError ?? "") }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "pencil.tip.crop.circle").font(.system(size: 32)).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text("PenActor").font(.title2.bold())
                Text("系统数位笔输入 · 调试面板").foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("窗口置顶", isOn: $monitor.alwaysOnTop).toggleStyle(.checkbox)
            Button("导出 JSON", systemImage: "square.and.arrow.up") { monitor.exportLog() }
                .disabled(monitor.isExporting)
                .help("导出全部设备最近 500 条事件，保留完整压力精度与系统时间戳")
            Button("清空记录", systemImage: "trash") { monitor.clear() }
            Button(monitor.isRunning ? "停止监听" : "开始监听",
                   systemImage: monitor.isRunning ? "stop.fill" : "play.fill") {
                if monitor.isRunning { monitor.stop() } else { monitor.start() }
            }.buttonStyle(.borderedProminent)
        }
    }

    private var permissionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(monitor.isRunning ? "监听已启动" : "监听已停止",
                      systemImage: monitor.isRunning ? "waveform" : "pause.circle")
                    .font(.headline)
                Spacer()
                Text("输入监控权限：\(monitor.listenAccess ? "已允许" : "未允许 / 待确认")")
                if !monitor.listenAccess {
                    Button("请求权限") { monitor.requestPermission() }
                }
                Button("重新检查") { monitor.recheck() }
            }
            HStack(spacing: 20) {
                status("本地", installed: monitor.installation.local, received: monitor.receivedLocal)
                status("全局", installed: monitor.installation.global, received: monitor.receivedGlobal)
                Spacer()
                Text("累计 \(monitor.snapshot.totalEvents) 个笔事件").monospacedDigit()
            }.font(.caption).foregroundStyle(.secondary)
            Text("在测试区或 PS / CSP 中使用笔以获取数据。未授权时仍可在本窗口测试；无事件不代表设备已断开。")
                .font(.caption).foregroundStyle(.secondary)
        }.panel()
    }

    private func status(_ title: String, installed: Bool, received: Bool) -> some View {
        Text("\(title)：\(installed ? "监听器已创建" : "未安装") · \(received ? "已收到笔事件" : "尚未收到笔事件")")
    }

    private var pencilInteractionPanel: some View {
        let interactions = monitor.pencilInteractions
        return VStack(alignment: .leading, spacing: 12) {
            Label("Pencil 手势 · 本应用窗口", systemImage: "hand.tap").font(.headline)
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("双击笔身").font(.subheadline.bold())
                    Text("\(interactions.doubleTapCount) 次").font(.title2.monospacedDigit())
                    Text(interactions.lastDoubleTapAt == nil ? "尚未收到" : "已收到双击")
                        .foregroundStyle(interactions.lastDoubleTapAt == nil ? Color.secondary : Color.accentColor)
                    Text("最近：\(interactionTime(interactions.lastDoubleTapAt))")
                    Text(interactions.doubleTapPaired ? "来源：changeMode + SwiftUI（已去重）" :
                         "来源：\(interactions.lastDoubleTapSource?.rawValue ?? "等待回调")")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("挤压 Pencil Pro").font(.subheadline.bold())
                    Text("\(interactions.squeezeCount) 次").font(.title2.monospacedDigit())
                    Text(interactions.squeezeStatus.rawValue)
                        .foregroundStyle(interactions.squeezeStatus == .active ? Color.green : Color.secondary)
                    Text("最近：\(interactionTime(interactions.lastSqueezeAt))")
                    Text("完成 \(interactions.squeezeCompletedCount) · 失败 / 取消 \(interactions.squeezeFailedCount) · 来源：SwiftUI")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.font(.callout).fixedSize(horizontal: false, vertical: true)
            Text("将 PenActor 窗口移到 iPad 并激活后测试。双击需在显示器的 iPad 设置中启用，挤压需 Pencil Pro。提示不归属到某支笔，也不表示可后台监听 PS / CSP 中的手势。")
                .font(.caption).foregroundStyle(.secondary)
            if #unavailable(macOS 14.5) {
                Text("当前系统仅接入 changeMode 双击事件；SwiftUI 双击 / 挤压回调需要 macOS 14.5 或更新版本。")
                    .font(.caption).foregroundStyle(.orange)
            }
        }.panel()
    }

    private func interactionTime(_ date: Date?) -> String {
        date?.formatted(.dateTime.hour().minute().second().secondFraction(.fractional(3))) ?? "—"
    }

    private var hardwarePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("已观察设备", systemImage: "ipad.and.arrow.forward").font(.headline)
            Toggle("笔变化时自动切换", isOn: Binding(
                get: { monitor.automaticallySwitchDevices },
                set: { monitor.setAutomaticSwitching($0) }
            )).toggleStyle(.checkbox)
            if monitor.snapshot.devices.isEmpty {
                Text("等待笔输入").font(.title3)
                Text("请让笔进入感应范围并落笔。Sidecar 请连接 iPad 后使用 Apple Pencil。")
                    .foregroundStyle(.secondary)
            } else {
                Picker("设备", selection: Binding(
                    get: { monitor.snapshot.selectedIdentity },
                    set: { monitor.selectDevice($0) }
                )) {
                    ForEach(monitor.snapshot.devices) { device in
                        Text(device.title).tag(Optional(device.id))
                    }
                }
                if let device {
                    Text(device.status).font(.caption).foregroundStyle(.secondary)
                    field("身份匹配方式", device.id.level.label)
                    field("配置匹配键", device.id.key)
                    field("当前会话 Device ID", identifierText(device.lastEvent.deviceID))
                    if let info = device.info {
                        field("工具类型", info.toolType)
                        field("Vendor ID", identifierText(info.vendorID))
                        field("Tablet ID", identifierText(info.tabletID))
                        field("System tablet ID", identifierText(info.systemTabletID))
                        field("Pointing device ID", identifierText(info.pointingDeviceID))
                        field("厂商工具类型", identifierText(info.vendorPointingDeviceType))
                        field("序列号", identifierText(info.serialNumber))
                        field("Unique ID", identifierText(info.uniqueID))
                        field("Capability mask", identifierText(info.capabilityMask))
                        Text("标识为系统 / 驱动报告值；0 可能是占位值，不据此识别硬件型号。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("硬件信息待获取").font(.headline)
                        Text("尚未收到 proximity 事件；可尝试抬笔离开感应范围后重新靠近。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Text("最多保留 32 个设备身份。同型号归组无法区分缺少唯一标识的多支笔；会话 ID 仅用于事件关联。")
                .font(.caption).foregroundStyle(.tertiary)
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }

    private var samplePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("实时读数").font(.headline)
                Spacer()
                if let event = device?.lastSampleEvent {
                    Text(event.source.rawValue).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(number(sample?.pressure.map(Double.init))).font(.system(size: 40, weight: .medium, design: .monospaced))
                Text("压力 / 1.0000").foregroundStyle(.secondary)
                Spacer()
            }
            ProgressView(value: Double(max(0, min(1, sample?.pressure ?? 0))))
            Text(PenCapability.pressure.support(mask: device?.info?.capabilityMask))
                .font(.caption).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
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
            Divider()
            if let event = device?.lastSampleEvent {
                Text("\(event.typeName) · uptime \(event.timestamp.formatted(.number.precision(.fractionLength(4)))) s")
                    .font(.caption.monospaced())
                Text("最近采样 \(event.receivedAt.formatted(date: .omitted, time: .standard)) · 前台应用（上下文）：\(event.foregroundApp)")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("等待有效采样；倾斜值为 −1…1，旋转值为笔轴角度。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("读数来自系统事件，可能已经过驱动曲线处理。零值不表示该能力一定受支持。")
                .font(.caption).foregroundStyle(.secondary)
        }.panel()
    }

    private var trendPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("压力趋势").font(.headline)
                Spacer()
                Text("最近 5 秒 · 最多 600 个采样").font(.caption).foregroundStyle(.secondary)
            }
            PressureTrend(events: device?.history ?? [])
                .frame(height: 80)
            Text("以最新事件时间为右端；停止输入后保留曲线，未取得压力处留空。")
                .font(.caption).foregroundStyle(.secondary)
        }.panel()
    }

    private var testPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("笔输入测试区").font(.headline)
                Spacer()
                Text("线宽随系统压力变化 · 仅接受笔事件").font(.caption).foregroundStyle(.secondary)
            }
            TestPad(isRunning: monitor.isRunning, clearGeneration: monitor.clearGeneration)
                .frame(height: 180)
            Text("使用 Sidecar 时请把此窗口移至 iPad。此区域是输入验证工具；不应用平滑或压力曲线。")
                .font(.caption).foregroundStyle(.secondary)
        }.panel()
    }

    private var eventsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            }.frame(height: 190)
        }.panel()
    }

    private func number(_ value: Double?) -> String {
        value.map { String(format: "%.4f", $0) } ?? "未取得"
    }

    private func metric(_ title: String, _ value: String, capability: PenCapability? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            if let capability {
                Text(capability.support(mask: device?.info?.capabilityMask))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
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
        padding(16)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 1))
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
