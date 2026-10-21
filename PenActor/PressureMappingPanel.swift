import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PressureMappingPanel: View {
    @ObservedObject var monitor: PenMonitor
    @State private var selected: UUID?
    @State private var draft: PressureProfile?
    @State private var selectedPoint: Int?
    init(monitor: PenMonitor, initialProfile: PressureProfile? = nil) {
        self.monitor = monitor
        _selected = State(initialValue: initialProfile?.id)
        _draft = State(initialValue: initialProfile)
    }
    private var device: PenIdentity? { monitor.snapshot.selectedIdentity }
    private var profiles: [PressureProfile] { monitor.profiles.filter { $0.device == device } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("压力重映射 · 实验", systemImage: "point.topleft.down.curvedto.point.bottomright.up").font(.headline)
                Spacer()
                Text("辅助功能：\(monitor.accessibilityAccess ? "已允许" : "未允许")")
                Button("请求辅助功能权限") { monitor.requestAccessibility() }
                Button("重新检查") { monitor.refreshPermission() }
            }
            ForEach(monitor.mapping.activeProfiles) { profile in
                Text("已启用：\(profile.name) · \(profile.device.key)").font(.caption).textSelection(.enabled)
            }
            Text(monitor.mapping.status).foregroundStyle(monitor.mapping.isRunning ? Color.green : Color.secondary)
            Text("仅作用于配置中的目标应用。回调已修改不代表 PS / CSP 已验证接收；应用事件层读数可能已是映射结果。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker("设备配置", selection: $selected) {
                    Text("选择配置").tag(UUID?.none)
                    ForEach(profiles) { p in Text(p.name).tag(Optional(p.id)) }
                }.frame(maxWidth: 350)
                Button("新增配置") {
                    guard let device else { return }
                    let p = PressureProfile(name: "新压力配置", device: device)
                    if monitor.saveProfile(p) { selected = p.id; draft = p }
                }.disabled(device == nil || device?.level == .session)
                if let draft {
                    Button("删除配置", role: .destructive) { monitor.deleteProfile(draft.id); selected = nil; self.draft = nil }
                }
            }
            if device?.level == .model { Text("当前按型号归组：同型号的多支 Pencil 将共用配置。重连后请让笔离开再进入感应范围，以便 tap 识别。 ").font(.caption).foregroundStyle(.secondary) }
            if draft != nil {
                editor
            }
            if let last = monitor.mapping.diagnostics.last {
                Text("Tap 输入 \(last.inputPressure, specifier: "%.4f") → 输出 \(last.outputPressure, specifier: "%.4f") · \(last.targetBundleID ?? "目标未知") · \(last.reason)")
                    .font(.caption).monospacedDigit()
                Text("设备：\(last.device?.key ?? "待识别") · 配置：\(monitor.profiles.first { $0.id == last.profileID }?.name ?? "透传") · 目标 PID \(last.targetPID)")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text("已修改 \(monitor.mapping.modifiedEventCount) 个事件；启用配置 \(monitor.enabledProfileIDs.count) 个。保存曲线和切换配置从下一笔生效；禁用立即透传。").font(.caption)
            if let error = monitor.profileError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
        .padding(16).background(.background, in: RoundedRectangle(cornerRadius: 12))
        .onAppear { selected = profiles.first?.id }
        .onChange(of: selected) { _, id in draft = monitor.profiles.first { $0.id == id }; selectedPoint = nil }
        .onChange(of: device) { _, _ in selected = profiles.first?.id; draft = monitor.profiles.first { $0.id == selected } }
    }
    private var editor: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack {
                PressureCurveEditor(curve: Binding(get: { draft?.curve ?? .linear }, set: { draft?.curve = $0 }), selected: $selectedPoint)
                    .frame(width: 300, height: 240)
                HStack {
                    Button("恢复线性") { draft?.curve = .linear; selectedPoint = nil }
                    Button("轻压增强") { draft?.curve = .light; selectedPoint = nil }
                    Button("删除点") {
                        if let i = selectedPoint, let n = draft?.curve.points.count, i > 0 && i < n-1 { draft?.curve.points.remove(at: i); selectedPoint = nil }
                    }.disabled(selectedPoint == nil || selectedPoint == 0 || selectedPoint == (draft?.curve.points.count ?? 0)-1)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                TextField("配置名称", text: Binding(get: { draft?.name ?? "" }, set: { draft?.name = $0 }))
                Text("目标应用（bundle ID）").font(.subheadline.bold())
                ForEach(draft?.targetBundleIDs ?? [], id: \.self) { id in
                    HStack { Text(id).font(.caption).textSelection(.enabled); Button("移除") { draft?.targetBundleIDs.removeAll { $0 == id } } }
                }
                HStack {
                    Menu("添加运行中的应用") {
                        ForEach(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }, id: \.processIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier!) { addTarget(app.bundleIdentifier!) }
                        }
                    }
                    Button("浏览 .app…") { browseApplication() }
                }
                Text("双击曲线区域添加点；拖拽内点调整。端点固定，输出保持单调。新配置默认线性，需要保存后启用。").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("保存") { if let draft { _ = monitor.saveProfile(draft) } }.disabled(draft?.isValid != true)
                    Button("保存并启用") {
                        if let draft, monitor.saveProfile(draft) { monitor.enableProfile(draft.id) }
                    }.disabled(draft?.isValid != true || draft?.targetBundleIDs.isEmpty != false || !monitor.isRunning)
                    if let draft, monitor.enabledProfileIDs.contains(draft.id) {
                        Button("禁用此配置") { monitor.disableProfile(draft.id) }
                    }
                }
            }.frame(maxWidth: .infinity)
        }
    }
    private func addTarget(_ id: String) { if draft?.targetBundleIDs.contains(id) == false { draft?.targetBundleIDs.append(id) } }
    private func browseApplication() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.canChooseDirectories = false
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier { addTarget(id) }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
}

struct PressureCurveEditor: View {
    @Binding var curve: PressureCurve
    @Binding var selected: Int?
    var body: some View {
        GeometryReader { geo in
            let size = CGSize(width: max(1, geo.size.width-40), height: max(1, geo.size.height-40))
            let origin = CGPoint(x: 30, y: 10)
            let position: (PressurePoint) -> CGPoint = { CGPoint(x: origin.x+$0.x*size.width, y: origin.y+(1-$0.y)*size.height) }
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    var grid = Path()
                    for i in 0...4 {
                        let f = Double(i)/4
                        grid.move(to: position(.init(x: f, y: 0))); grid.addLine(to: position(.init(x: f, y: 1)))
                        grid.move(to: position(.init(x: 0, y: f))); grid.addLine(to: position(.init(x: 1, y: f)))
                    }
                    context.stroke(grid, with: .color(.secondary.opacity(0.3)))
                    var line = Path()
                    for i in 0...200 { let x = Double(i)/200; let p = position(.init(x: x, y: curve.map(x))); if i == 0 { line.move(to: p) } else { line.addLine(to: p) } }
                    context.stroke(line, with: .color(.accentColor), lineWidth: 2)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { location in
                    let x = min(0.999, max(0.001, (location.x-origin.x)/size.width))
                    guard curve.points.count < 32, !curve.points.contains(where: { abs($0.x-x) < 0.005 }) else { return }
                    let i = curve.points.firstIndex { $0.x > x }!
                    let y = min(curve.points[i].y, max(curve.points[i-1].y, 1-(location.y-origin.y)/size.height))
                    curve.points.insert(.init(x: x, y: y), at: i); selected = i
                }
                ForEach(curve.points.indices, id: \.self) { i in
                    Circle().fill(selected == i ? Color.orange : Color.accentColor).frame(width: 12, height: 12)
                        .position(position(curve.points[i]))
                        .onTapGesture { selected = i }
                        .gesture(DragGesture(coordinateSpace: .named("curve")).onChanged { value in
                            selected = i
                            guard i > 0 && i < curve.points.count-1 else { return }
                            let left = curve.points[i-1], right = curve.points[i+1]
                            let gap = min(0.001, (right.x-left.x)/4)
                            curve.points[i] = .init(x: min(right.x-gap, max(left.x+gap, (value.location.x-origin.x)/size.width)),
                                y: min(right.y, max(left.y, 1-(value.location.y-origin.y)/size.height)))
                        })
                }
                Text("输出 100%").font(.caption2).offset(x: 0, y: -5)
                Text("0%").font(.caption2).position(x: origin.x, y: origin.y+size.height+12)
                Text("输入压力").font(.caption2).position(x: origin.x+size.width/2, y: origin.y+size.height+12)
                Text("100%").font(.caption2).position(x: origin.x+size.width-10, y: origin.y+size.height+12)
            }.coordinateSpace(name: "curve")
        }
    }
}
