import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PreferencesPageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title3.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct GeneralPreferencesView: View {
    @ObservedObject var monitor: PenMonitor
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                    Text("若列表中没有 PenActor，请点 + 添加 /Applications/PenActor.app。授权后按系统提示重新打开应用；窗口内测试无需输入监控权限。")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    if let error = monitor.permissionError { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                }.padding(10)
            }
            GroupBox("随航触摸 · 实验") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("屏蔽触摸长按右键（实验）", isOn: Binding(get: { monitor.touchBlocking.enabled }, set: { monitor.setTouchBlocking($0) }))
                        .toggleStyle(.checkbox)
                    HStack {
                        Text(monitor.touchBlocking.status).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("观察右键 \(monitor.touchBlocking.observedCount) · 拦截 \(monitor.touchBlocking.suppressedPressCount) 次 / \(monitor.touchBlocking.suppressedEventCount) 事件").font(.caption.monospacedDigit())
                    }
                    HStack {
                        Text("生效应用").font(.caption)
                        ApplicationPicker { id, _ in monitor.addTouchBlockingTarget(id) }
                        Menu("已选 \(monitor.touchBlockingTargets.count) 个 · 移除…") {
                            ForEach(monitor.touchBlockingTargets, id: \.self) { id in
                                Button(id, role: .destructive) { monitor.removeTouchBlockingTarget(id) }
                            }
                        }.disabled(monitor.touchBlockingTargets.isEmpty)
                        Spacer()
                    }
                    Text(monitor.touchBlockingTargets.joined(separator: "、")).font(.caption).foregroundStyle(.secondary).lineLimit(2).help(monitor.touchBlockingTargets.joined(separator: "\n"))
                    Text("仅拦截所选应用中带 touch 标记的右键；双指缩放、旋转、滚动不参与过滤。尚未确认随航长按是否携带此标记，计数为 0 不代表长按已关闭。需辅助功能权限；重启后默认关闭。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let error = monitor.touchBlockingError { Text(error).font(.caption).foregroundStyle(.red) }
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
            errorMessage
        }.padding(16)
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

/// A draft is dirty only when its values differ, never merely because a field sent a setter.
struct DeviceProfileDraftState {
    var device: DevicePressureDefaults?
    var profile: PressureProfile?
    private var savedDevice: DevicePressureDefaults?
    private var savedProfile: PressureProfile?
    var hasChanges: Bool { device != savedDevice || profile != savedProfile }
    mutating func load(device: DevicePressureDefaults?, profile: PressureProfile?) {
        self.device = device; self.profile = profile
        savedDevice = device; savedProfile = profile
    }
    mutating func setDeviceName(_ name: String, for identity: PenIdentity) {
        guard device?.device == identity else { return }
        device?.name = name
    }
    mutating func setProfileName(_ name: String, for id: UUID?) {
        guard let id, profile?.id == id else { return }
        profile?.name = name
    }
    mutating func didSaveDevice(_ value: DevicePressureDefaults) { savedDevice = value }
    mutating func didSaveProfile(_ value: PressureProfile) { savedProfile = value }
}

struct DeviceProfilesPreferencesView: View {
    @ObservedObject var monitor: PenMonitor
    @State private var selected: PenIdentity?
    @State private var profileID: UUID?
    @State private var draft = DeviceProfileDraftState()
    private var deviceDraft: DevicePressureDefaults? {
        get { draft.device }
        nonmutating set { draft.device = newValue }
    }
    private var profileDraft: PressureProfile? {
        get { draft.profile }
        nonmutating set { draft.profile = newValue }
    }
    @FocusState private var focusedField: EditorField?
    private enum EditorField: Hashable { case deviceName, profileName }
    @State private var saved = false
    private var dirty: Bool { draft.hasChanges }
    @State private var didLoad = false
    @State private var pendingDevice: PenIdentity?
    @State private var pendingProfile: UUID?
    @State private var switchingDevice = false
    @State private var confirmDiscard = false
    init(monitor: PenMonitor, initialProfile: PressureProfile? = nil) {
        self.monitor = monitor
        _selected = State(initialValue: initialProfile?.device)
        _profileID = State(initialValue: initialProfile?.id)
    }
    private var identities: [PenIdentity] {
        var result = monitor.mappingDefaults.devices.map(\.device)
        for id in monitor.snapshot.devices.map(\.id) + monitor.profiles.map(\.device) where !result.contains(id) { result.append(id) }
        return result
    }
    private var profiles: [PressureProfile] { monitor.profiles.filter { $0.device == selected } }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("设备").font(.headline).padding(16)
                List(selection: Binding(get: { selected }, set: { requestDevice($0) })) {
                    ForEach(identities, id: \.self) { id in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(monitor.deviceDisplayName(id), systemImage: "pencil.tip").lineLimit(2)
                            Text(activeName(id)).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 5).tag(id)
                    }
                }.listStyle(.sidebar)
            }.frame(width: 180)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let selected, deviceDraft != nil {
                        PreferencesPageHeader(title: monitor.deviceDisplayName(selected), subtitle: "先调整这台设备的默认笔压，再为配置添加生效应用；需要时才单独覆盖。")
                        HStack {
                            TextField("设备名称（留空使用系统名称）", text: Binding(get: { deviceDraft?.name ?? "" }, set: { draft.setDeviceName($0, for: selected); changed() }))
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .deviceName)
                            Button("保存名称") { saveName() }.disabled(deviceDraft?.isValid != true || selected.level == .session)
                        }
                        DisclosureGroup("设备身份 · \(selected.level.label)") {
                            Text(selected.key).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            if selected.level == .model {
                                Text("此身份按型号归组，不能区分多支同型号的笔；重命名不改变匹配身份。").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if selected.level == .session {
                            Text("等待 proximity 硬件元数据后才能保存持久配置。请让笔离开再进入感应范围。").foregroundStyle(.secondary)
                        } else {
                            HStack {
                                Picker("编辑", selection: Binding(get: { profileID }, set: { requestProfile($0) })) {
                                    Text("设备默认").tag(UUID?.none)
                                    ForEach(profiles) { Text($0.name).tag(Optional($0.id)) }
                                }
                                Button("新增配置") { create(selected) }.disabled(dirty)
                            }
                            if profileID == nil { deviceEditor }
                            else if profileDraft != nil { profileEditor.id(profileID) }
                        }
                    } else {
                        PreferencesPageHeader(title: "配置", subtitle: "每台设备独立设置，配置中的应用默认继承所属设备。")
                        ContentUnavailableView("等待数位笔", systemImage: "pencil.tip", description: Text("连接 Sidecar 或数位板，让笔进入感应范围并落笔。保存过的设备会一直显示在左侧。"))
                    }
                    if let error = monitor.profileError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }.padding(16).id(selected)
            }.frame(maxWidth: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let selected, selected.level != .session {
                        VStack(spacing: 0) { Divider(); editingActions }.background(.bar)
                    }
                }
        }.onAppear {
            focusedField = nil
            if !didLoad {
                if selected == nil { selected = identities.first }
                load(); didLoad = true
            }
        }.onDisappear { focusedField = nil }
        .onChange(of: identities) { _, ids in
            if selected == nil { selected = ids.first; load() }
        }
        .confirmationDialog("放弃尚未保存的更改？", isPresented: $confirmDiscard) {
            Button("放弃更改", role: .destructive) {
                if switchingDevice { selected = pendingDevice; profileID = nil }
                else { profileID = pendingProfile }
                load()
            }
            Button("继续编辑", role: .cancel) { }
        } message: { Text("切换后将加载已保存的设备设置或配置。") }
    }
    private var deviceEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("设备默认压力设置") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("此处的曲线和入锋 / 出锋仅属于当前设备。配置中选择继承的应用会共同使用它。")
                        .font(.caption).foregroundStyle(.secondary)
                    PressureConfigurationEditor(configuration: Binding(get: { deviceDraft?.configuration ?? PressureConfiguration() }, set: { deviceDraft?.configuration = $0; changed() }))
                }.padding(10)
            }
            Text("设备默认值不会自动启用映射，请添加配置和生效应用。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var profileEditor: some View {
        let editingProfileID = profileDraft?.id
        return VStack(alignment: .leading, spacing: 12) {
            TextField("配置名称", text: Binding(get: { profileDraft?.name ?? "" }, set: { draft.setProfileName($0, for: editingProfileID); changed() }))
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .profileName)
            GroupBox("生效应用") {
                VStack(alignment: .leading, spacing: 0) {
                    if profileDraft?.applicationRules?.isEmpty != false {
                        Text("添加一个或多个软件，默认继承当前设备的压力设置。").foregroundStyle(.secondary).padding(10)
                    }
                    ForEach(profileDraft?.applicationRules ?? []) { rule in
                        ApplicationRuleRow(rule: ruleBinding(rule.bundleID), base: deviceDraft?.configuration ?? PressureConfiguration(), remove: {
                            profileDraft?.applicationRules?.removeAll { $0.bundleID == rule.bundleID }; changed()
                        })
                        Divider()
                    }
                    HStack { ApplicationPicker(add: addApplication); Spacer() }.padding(10)
                }
            }
            Text("继承会随设备默认更新；单独覆盖仅影响本配置中的这个应用。未列出的应用保持透传。")
                .font(.caption).foregroundStyle(.secondary)
            Text("每台设备同时启用一个配置，各设备互不影响。保存从下一笔生效；禁用或暂停立即停止修改。首次启用后请让笔重新进入感应范围。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var editingActions: some View {
        HStack {
            if profileID == nil {
                Text("设备默认设置").font(.caption).foregroundStyle(.secondary)
                savedLabel
                Spacer()
                Button("保存设备默认") { saveDevice() }.buttonStyle(.borderedProminent).disabled(deviceDraft?.isValid != true)
            } else {
                Button("删除配置", role: .destructive) {
                    if let id = profileDraft?.id {
                        monitor.deleteProfile(id)
                        if !monitor.profiles.contains(where: { $0.id == id }) { profileID = nil; load() }
                    }
                }
                Spacer()
                savedLabel
                Button("保存配置") { saveProfile() }.disabled(profileDraft?.isValid != true)
                if let id = profileDraft?.id, monitor.enabledProfileIDs.contains(id) {
                    Button("禁用此配置") { monitor.disableProfile(id) }
                } else {
                    Button("保存并启用") { if saveProfile(), let id = profileDraft?.id { monitor.enableProfile(id) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(profileDraft?.isValid != true || profileDraft?.effectiveTargetBundleIDs.isEmpty != false || !monitor.isRunning)
                }
            }
        }.padding(.horizontal, 16).padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("当前设备或配置的编辑操作")
    }

    private var savedLabel: some View {
        Group {
            if dirty { Text("未保存").foregroundStyle(.orange) }
            else if saved { Text("已保存").foregroundStyle(.secondary) }
        }.font(.caption)
    }
    private func activeName(_ id: PenIdentity) -> String {
        monitor.profiles.first { $0.device == id && monitor.enabledProfileIDs.contains($0.id) }.map { "已启用 · "+$0.name } ?? "未启用映射"
    }
    private func changed() { saved = false }
    private func finishEditing() {
        focusedField = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
    private func load() {
        focusedField = nil
        let device = selected.map { monitor.mappingDefaults.settings(for: $0) }
        let profile = monitor.profiles.first { $0.id == profileID && $0.device == selected }
        profileID = profile?.id
        draft.load(device: device, profile: profile)
        saved = false
    }
    private func requestDevice(_ id: PenIdentity?) {
        guard selected != id else { return }
        finishEditing()
        if dirty { pendingDevice = id; switchingDevice = true; confirmDiscard = true }
        else { selected = id; profileID = nil; load() }
    }
    private func requestProfile(_ id: UUID?) {
        guard profileID != id else { return }
        finishEditing()
        if dirty { pendingProfile = id; switchingDevice = false; confirmDiscard = true }
        else { profileID = id; load() }
    }
    @discardableResult private func saveName() -> Bool {
        guard var settings = deviceDraft else { return false }
        let stored = monitor.mappingDefaults.settings(for: settings.device)
        if settings.name == stored.name { return true }
        settings.configuration = monitor.mappingDefaults.settings(for: settings.device).configuration
        settings.name = settings.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if monitor.saveDeviceSettings(settings) {
            deviceDraft?.name = settings.name
            draft.didSaveDevice(settings)
            saved = true
            return true
        }
        return false
    }
    private func saveDevice() {
        if let settings = deviceDraft, monitor.saveDeviceSettings(settings) { draft.didSaveDevice(settings); saved = true }
    }
    @discardableResult private func saveProfile() -> Bool {
        // Name editing is independent of the profile; never overwrite the device's curve here.
        guard let profileDraft, saveName(), monitor.saveProfile(profileDraft) else { return false }
        draft.didSaveProfile(profileDraft)
        saved = true; return true
    }
    private func create(_ identity: PenIdentity) {
        let profile = PressureProfile(name: "配置 \(profiles.count+1)", device: identity, applicationRules: [])
        if monitor.saveProfile(profile) { profileID = profile.id; load(); saved = true }
    }
    private func addApplication(_ id: String, _ name: String) {
        guard profileDraft?.applicationRules?.contains(where: { $0.bundleID == id }) == false else { return }
        var rule = ApplicationPressureRule(bundleID: id, name: name)
        rule.configuration = deviceDraft?.configuration ?? PressureConfiguration()
        profileDraft?.applicationRules?.append(rule); changed()
    }
    private func ruleBinding(_ id: String) -> Binding<ApplicationPressureRule> {
        Binding(get: { profileDraft?.applicationRules?.first { $0.bundleID == id } ?? ApplicationPressureRule(bundleID: id, name: id) }, set: { value in
            if let i = profileDraft?.applicationRules?.firstIndex(where: { $0.bundleID == id }) { profileDraft?.applicationRules?[i] = value; changed() }
        })
    }
}

private struct ApplicationRuleRow: View {
    @Binding var rule: ApplicationPressureRule
    let base: PressureConfiguration
    var remove: () -> Void
    @State private var editing = false
    private var icon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
    var body: some View {
        HStack(spacing: 12) {
            if let icon { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
            else { Image(systemName: "app").font(.title2).frame(width: 28) }
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name).lineLimit(1)
                Text(rule.mode.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("继承设备默认", isOn: Binding(get: { rule.mode == .inherit }, set: { inherit in
                rule.mode = inherit ? .inherit : .custom
                if !inherit { editing = true }
            })).toggleStyle(.checkbox).disabled(rule.mode == .passthrough)
            Button { editing = true } label: { Image(systemName: "slider.horizontal.3") }
                .help("设置此应用的继承、覆盖或透传")
                .popover(isPresented: $editing, arrowEdge: .trailing) {
                    ApplicationRuleEditor(rule: $rule, base: base).padding(16).frame(width: 600)
                }
            Button(role: .destructive, action: remove) { Image(systemName: "minus.circle") }.help("移除此应用")
        }.padding(10)
    }
}

struct ApplicationRuleEditor: View {
    @Binding var rule: ApplicationPressureRule
    let base: PressureConfiguration
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PreferencesPageHeader(title: rule.name, subtitle: "仅影响当前设备的这个配置；完成后保存配置。")
            Text(rule.bundleID).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Picker("压力设置", selection: $rule.mode) {
                ForEach(ApplicationPressureRule.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            if rule.mode == .custom {
                PressureConfigurationEditor(configuration: $rule.configuration)
                Button("复制当前设备默认") { rule.configuration = base }
            } else {
                Text(rule.mode == .inherit ? "使用所属设备的默认压力曲线与入锋 / 出锋；设备默认保存后，从下一笔跟随更新。" : "当前应用保留系统输入压力，不应用此配置的曲线或入锋 / 出锋。")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
