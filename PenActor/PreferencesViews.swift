import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PreferencesPageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GeneralPreferencesView: View {
    @ObservedObject var monitor: PenMonitor
    @State private var draft = PressureConfiguration()
    @State private var saved = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PreferencesPageHeader(title: "通用", subtitle: "PenActor 在菜单栏持续运行，关闭设置窗口后仍会处理已启用的笔输入。")
                GroupBox("运行与启动") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(monitor.isRunning ? "输入服务运行中" : "输入服务已停止", systemImage: monitor.isRunning ? "checkmark.circle.fill" : "pause.circle")
                                .foregroundStyle(monitor.isRunning ? Color.green : Color.secondary)
                            Spacer()
                            Button(monitor.isRunning ? "停止服务" : "启动服务") { if monitor.isRunning { monitor.stop() } else { monitor.start() } }
                        }
                        Toggle("启动 PenActor 后自动监听", isOn: Binding(get: { monitor.startMonitoringOnLaunch }, set: { monitor.setStartMonitoringOnLaunch($0) }))
                        Toggle("启动时打开设置窗口", isOn: Binding(get: { monitor.showSettingsOnLaunch }, set: { monitor.setShowSettingsOnLaunch($0) }))
                        Text("重启程序后映射默认关闭，需手动启用硬件配置。可从菜单栏随时打开设置、暂停映射或退出。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(10).toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("访问权限") {
                    VStack(spacing: 12) {
                        permissionRow("输入监控", allowed: monitor.listenAccess) { monitor.requestPermission() }
                        permissionRow("辅助功能", allowed: monitor.accessibilityAccess) { monitor.requestAccessibility() }
                        HStack { Text("本窗口测试可在未授予输入监控权限时使用。").font(.caption).foregroundStyle(.secondary); Spacer(); Button("重新检查") { monitor.refreshPermission() } }
                    }.padding(10)
                }
                GroupBox("全局压力默认值") {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("供选择“沿用默认”的硬件配置使用。应用自定义可覆盖此处；不会自动启用任何硬件。")
                            .font(.caption).foregroundStyle(.secondary)
                        PressureConfigurationEditor(configuration: $draft)
                        HStack {
                            Spacer()
                            if saved { Text("已保存，下一笔生效").font(.caption).foregroundStyle(.secondary) }
                            Button("保存全局默认") {
                                var defaults = monitor.mappingDefaults; defaults.global = draft
                                saved = monitor.saveDefaults(defaults)
                            }.buttonStyle(.borderedProminent).disabled(!draft.isValid)
                        }
                    }.padding(12)
                }
                errorMessage
            }.padding(24)
        }.onAppear { draft = monitor.mappingDefaults.global }
            .onChange(of: draft) { _, _ in saved = false }
    }
    private var errorMessage: some View { Group { if let error = monitor.profileError { Text(error).foregroundStyle(.red).textSelection(.enabled) } } }
    private func permissionRow(_ name: String, allowed: Bool, action: @escaping () -> Void) -> some View {
        HStack { Label(name, systemImage: allowed ? "checkmark.shield" : "lock"); Spacer(); Text(allowed ? "已允许" : "未允许 / 待确认").foregroundStyle(.secondary); Button("请求权限", action: action).disabled(allowed) }
    }
}

struct ApplicationPicker: View {
    var add: (String, String) -> Void
    var body: some View {
        Menu {
            ForEach(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }, id: \.processIdentifier) { app in
                Button(app.localizedName ?? app.bundleIdentifier!) { add(app.bundleIdentifier!, app.localizedName ?? app.bundleIdentifier!) }
            }
            Divider()
            Button("浏览应用程序…") { browse() }
        } label: { Label("添加应用", systemImage: "plus") }
    }
    private func browse() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.application]; panel.canChooseDirectories = false
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
            add(id, url.deletingPathExtension().lastPathComponent)
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
}

struct ApplicationPreferencesView: View {
    @ObservedObject var monitor: PenMonitor
    @State private var selected: String?
    @State private var draft: ApplicationPressureRule?
    @State private var saved = false
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selected) {
                    ForEach(monitor.mappingDefaults.applications) { rule in
                        VStack(alignment: .leading, spacing: 3) { Text(rule.name); Text(rule.mode.title).font(.caption).foregroundStyle(.secondary) }.tag(rule.bundleID)
                    }
                }.listStyle(.sidebar)
                Divider()
                HStack { ApplicationPicker(add: add); Spacer() }.padding(12)
            }.frame(width: 220)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PreferencesPageHeader(title: draft?.name ?? "应用", subtitle: "为绘画应用设置默认响应，或让该应用中的所有设备透传。")
                    if draft != nil {
                        Text(draft!.bundleID).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Picker("输入处理", selection: Binding(get: { draft?.mode ?? .inherit }, set: { draft?.mode = $0; saved = false })) {
                            ForEach(ApplicationPressureRule.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                        if draft?.mode == .custom {
                            GroupBox {
                                PressureConfigurationEditor(configuration: Binding(get: { draft?.configuration ?? PressureConfiguration() }, set: { draft?.configuration = $0; saved = false })).padding(12)
                            }
                        } else {
                            GroupBox {
                                Label(draft?.mode == .passthrough ? "此应用透传所有笔压力，覆盖硬件自定义选择。" : "此应用使用通用页的全局压力默认值。", systemImage: draft?.mode == .passthrough ? "arrow.right" : "link")
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                            }
                        }
                        Text("应用默认只供“沿用默认”的硬件配置使用。硬件自定义优先于应用默认；应用透传优先于硬件。保存后从下一笔生效。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("移除应用设置", role: .destructive) { remove() }
                            Spacer()
                            if saved { Text("已保存").font(.caption).foregroundStyle(.secondary) }
                            Button("保存应用设置") { save() }.buttonStyle(.borderedProminent).disabled(draft?.isValid != true)
                        }
                    } else {
                        ContentUnavailableView("添加绘画应用", systemImage: "app.badge", description: Text("选择正在运行的 Photoshop、CSP，或浏览 .app。再到硬件页选择哪些笔在该应用生效。"))
                    }
                    if let error = monitor.profileError { Text(error).foregroundStyle(.red) }
                }.padding(24)
            }.frame(maxWidth: .infinity)
        }.onAppear { if selected == nil { selected = monitor.mappingDefaults.applications.first?.bundleID }; load() }
            .onChange(of: selected) { _, _ in load() }
    }
    private func load() { draft = monitor.mappingDefaults.applications.first { $0.bundleID == selected }; saved = false }
    private func add(_ id: String, _ name: String) {
        if !monitor.mappingDefaults.applications.contains(where: { $0.bundleID == id }) {
            var defaults = monitor.mappingDefaults
            defaults.applications.append(.init(bundleID: id, name: name))
            guard monitor.saveDefaults(defaults) else { return }
        }
        selected = id; load()
    }
    private func save() {
        guard let draft else { return }
        var defaults = monitor.mappingDefaults
        if let i = defaults.applications.firstIndex(where: { $0.bundleID == draft.bundleID }) { defaults.applications[i] = draft }
        saved = monitor.saveDefaults(defaults)
    }
    private func remove() {
        guard let draft else { return }
        var defaults = monitor.mappingDefaults
        defaults.applications.removeAll { $0.bundleID == draft.bundleID }
        if monitor.saveDefaults(defaults) { selected = nil; self.draft = nil }
    }
}

struct HardwarePreferencesView: View {
    @ObservedObject var monitor: PenMonitor
    @State private var selected: PenIdentity?
    @State private var profileID: UUID?
    @State private var draft: PressureProfile?
    @State private var saved = false
    init(monitor: PenMonitor, initialProfile: PressureProfile? = nil) {
        self.monitor = monitor; _selected = State(initialValue: initialProfile?.device)
        _profileID = State(initialValue: initialProfile?.id); _draft = State(initialValue: initialProfile)
    }
    private var identities: [PenIdentity] {
        var result = monitor.snapshot.devices.map(\.id)
        for profile in monitor.profiles where !result.contains(profile.device) { result.append(profile.device) }
        return result
    }
    private var profiles: [PressureProfile] { monitor.profiles.filter { $0.device == selected } }
    private func title(_ id: PenIdentity) -> String {
        monitor.snapshot.devices.first { $0.id == id }?.title ?? monitor.profiles.first { $0.device == id }?.name ?? id.key
    }
    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selected) {
                ForEach(identities, id: \.self) { id in
                    VStack(alignment: .leading, spacing: 5) {
                        Label(title(id), systemImage: "pencil.tip")
                        Text(monitor.profiles.contains { $0.device == id && monitor.enabledProfileIDs.contains($0.id) } ? "映射已启用" : "未启用映射")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4).tag(id)
                }
            }.listStyle(.sidebar).frame(width: 220)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PreferencesPageHeader(title: selected.map(title) ?? "硬件", subtitle: "按稳定设备身份管理配置，选择生效应用并手动启用。")
                    if let selected {
                        Text(selected.level.label).font(.caption).foregroundStyle(.secondary)
                        Text(selected.key).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack {
                            Picker("配置", selection: $profileID) {
                                Text("选择配置").tag(UUID?.none)
                                ForEach(profiles) { Text($0.name).tag(Optional($0.id)) }
                            }
                            Button("新增配置") { create(selected) }.disabled(selected.level == .session)
                        }
                        if selected.level == .model { Text("此身份按型号归组，同型号多支笔共用配置。首次启用后让笔离开再进入感应范围。").font(.caption).foregroundStyle(.secondary) }
                        if draft != nil { profileEditor }
                        else { Text(selected.level == .session ? "等待 proximity 元数据后才能创建持久配置。" : "为这支笔新增一个配置，选择目标应用。").foregroundStyle(.secondary) }
                    } else {
                        ContentUnavailableView("等待数位笔", systemImage: "pencil.tip", description: Text("连接 Sidecar 或数位板，让笔进入感应范围并落笔。已保存的硬件配置在重启后仍可编辑。"))
                    }
                    if let error = monitor.profileError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }.padding(24)
            }.frame(maxWidth: .infinity)
        }.onAppear {
            if selected == nil { selected = identities.first }
            if draft == nil { loadDevice() }
        }.onChange(of: selected) { _, _ in loadDevice() }
            .onChange(of: profileID) { _, id in draft = monitor.profiles.first { $0.id == id }; saved = false }
            .onChange(of: identities) { _, ids in if selected == nil { selected = ids.first } }
    }
    private var profileEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            TextField("配置名称", text: Binding(get: { draft?.name ?? "" }, set: { draft?.name = $0; saved = false }))
                .textFieldStyle(.roundedBorder)
            GroupBox("生效应用") {
                VStack(alignment: .leading, spacing: 10) {
                    let ids = Array(Set(monitor.mappingDefaults.applications.map(\.bundleID)+(draft?.targetBundleIDs ?? []))).sorted()
                    ForEach(ids, id: \.self) { id in
                        Toggle(monitor.mappingDefaults.applications.first { $0.bundleID == id }?.name ?? id, isOn: Binding(
                            get: { draft?.targetBundleIDs.contains(id) == true }, set: { enabled in
                                if enabled { draft?.targetBundleIDs.append(id) } else { draft?.targetBundleIDs.removeAll { $0 == id } }; saved = false
                            }))
                    }
                    ApplicationPicker { id, name in
                        var defaults = monitor.mappingDefaults
                        if !defaults.applications.contains(where: { $0.bundleID == id }) { defaults.applications.append(.init(bundleID: id, name: name)) }
                        if monitor.saveDefaults(defaults), draft?.targetBundleIDs.contains(id) == false { draft?.targetBundleIDs.append(id); saved = false }
                    }
                    if draft?.targetBundleIDs.isEmpty == true { Text("至少选择一个应用才能启用。").font(.caption).foregroundStyle(.secondary) }
                }.padding(10).toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle("沿用应用 / 全局默认压力设置", isOn: Binding(get: { draft?.usesDefaults ?? false }, set: { draft?.usesDefaults = $0; saved = false }))
                .toggleStyle(.checkbox)
            if draft?.usesDefaults == true {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("应用自定义 → 全局默认").font(.headline)
                        Text("前往通用或应用页调整曲线。取消沿用后，可为当前硬件单独设置；原有硬件自定义值会保留。")
                            .font(.callout).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
            } else {
                GroupBox { PressureConfigurationEditor(configuration: Binding(
                    get: { PressureConfiguration(curve: draft?.curve ?? .linear, taper: draft?.taper ?? StrokeTaperSettings()) },
                    set: { draft?.curve = $0.curve; draft?.taper = $0.taper; saved = false })).padding(12) }
            }
            HStack {
                Button("删除配置", role: .destructive) { if let id = draft?.id { monitor.deleteProfile(id); loadDevice() } }
                Spacer()
                if saved { Text("已保存").font(.caption).foregroundStyle(.secondary) }
                Button("保存") { if let draft { saved = monitor.saveProfile(draft) } }.disabled(draft?.isValid != true)
                if let id = draft?.id, monitor.enabledProfileIDs.contains(id) {
                    Button("禁用此配置") { monitor.disableProfile(id) }
                } else {
                    Button("保存并启用") { if let draft, monitor.saveProfile(draft) { saved = true; monitor.enableProfile(draft.id) } }
                        .buttonStyle(.borderedProminent).disabled(draft?.isValid != true || draft?.targetBundleIDs.isEmpty != false || !monitor.isRunning)
                }
            }
            Text("选择页面中的硬件不会改变已启用配置。保存从下一笔生效，禁用立即停止；应用透传优先于硬件自定义。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func loadDevice() { profileID = profiles.first?.id; draft = profiles.first; saved = false }
    private func create(_ identity: PenIdentity) {
        let profile = PressureProfile(name: "配置 \(profiles.count+1)", device: identity, usesDefaults: true)
        if monitor.saveProfile(profile) { profileID = profile.id; draft = profile; saved = true }
    }
}
