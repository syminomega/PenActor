import SwiftUI
import AppKit

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
                Text(String(localized: "设备")).font(.headline).padding(16)
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
                        PreferencesPageHeader(title: monitor.deviceDisplayName(selected), subtitle: String(localized: "先调整这台设备的默认笔压，再为配置添加生效应用；需要时才单独覆盖。"))
                        HStack {
                            TextField(String(localized: "设备名称（留空使用系统名称）"), text: Binding(get: { deviceDraft?.name ?? "" }, set: { draft.setDeviceName($0, for: selected); changed() }))
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .deviceName)
                            Button(String(localized: "保存名称")) { saveName() }.disabled(deviceDraft?.isValid != true || selected.level == .session)
                        }
                        DisclosureGroup(String(localized: "设备身份 · \(selected.level.label)")) {
                            Text(selected.key).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            if selected.level == .model {
                                Text(String(localized: "此身份按型号归组，不能区分多支同型号的笔；重命名不改变匹配身份。")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if selected.level == .session {
                            Text(String(localized: "等待 proximity 硬件元数据后才能保存持久配置。请让笔离开再进入感应范围。")).foregroundStyle(.secondary)
                        } else {
                            HStack {
                                Picker(String(localized: "编辑"), selection: Binding(get: { profileID }, set: { requestProfile($0) })) {
                                    Text(String(localized: "设备默认")).tag(UUID?.none)
                                    ForEach(profiles) { Text($0.name).tag(Optional($0.id)) }
                                }
                                Button(String(localized: "新增配置")) { create(selected) }.disabled(dirty)
                            }
                            if profileID == nil { deviceEditor }
                            else if profileDraft != nil { profileEditor.id(profileID) }
                        }
                    } else {
                        PreferencesPageHeader(title: String(localized: "配置"), subtitle: String(localized: "每台设备独立设置，配置中的应用默认继承所属设备。"))
                        ContentUnavailableView(String(localized: "等待数位笔"), systemImage: "pencil.tip", description: Text(String(localized: "连接 Sidecar 或数位板，让笔进入感应范围并落笔。保存过的设备会一直显示在左侧。")))
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
        .confirmationDialog(String(localized: "放弃尚未保存的更改？"), isPresented: $confirmDiscard) {
            Button(String(localized: "放弃更改"), role: .destructive) {
                if switchingDevice { selected = pendingDevice; profileID = nil }
                else { profileID = pendingProfile }
                load()
            }
            Button(String(localized: "继续编辑"), role: .cancel) { }
        } message: { Text(String(localized: "切换后将加载已保存的设备设置或配置。")) }
    }
    private var deviceEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox(String(localized: "设备默认压力设置")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "此处的曲线和入锋 / 出锋仅属于当前设备。配置中选择继承的应用会共同使用它。"))
                        .font(.caption).foregroundStyle(.secondary)
                    PressureConfigurationEditor(configuration: Binding(get: { deviceDraft?.configuration ?? PressureConfiguration() }, set: { deviceDraft?.configuration = $0; changed() }))
                }.padding(10)
            }
            Text(String(localized: "设备默认值不会自动启用映射，请添加配置和生效应用。")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var profileEditor: some View {
        let editingProfileID = profileDraft?.id
        return VStack(alignment: .leading, spacing: 12) {
            TextField(String(localized: "配置名称"), text: Binding(get: { profileDraft?.name ?? "" }, set: { draft.setProfileName($0, for: editingProfileID); changed() }))
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .profileName)
            GroupBox(String(localized: "生效应用")) {
                VStack(alignment: .leading, spacing: 0) {
                    if profileDraft?.applicationRules?.isEmpty != false {
                        Text(String(localized: "添加一个或多个软件，默认继承当前设备的压力设置。")).foregroundStyle(.secondary).padding(10)
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
            Text(String(localized: "继承会随设备默认更新；单独覆盖仅影响本配置中的这个应用。未列出的应用保持透传。"))
                .font(.caption).foregroundStyle(.secondary)
            Text(String(localized: "每台设备同时启用一个配置，各设备互不影响。保存从下一笔生效；禁用或暂停立即停止修改。首次启用后请让笔重新进入感应范围。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var editingActions: some View {
        HStack {
            if profileID == nil {
                Text(String(localized: "设备默认设置")).font(.caption).foregroundStyle(.secondary)
                savedLabel
                Spacer()
                Button(String(localized: "保存设备默认")) { saveDevice() }.buttonStyle(.borderedProminent).disabled(deviceDraft?.isValid != true)
            } else {
                Button(String(localized: "删除配置"), role: .destructive) {
                    if let id = profileDraft?.id {
                        monitor.deleteProfile(id)
                        if !monitor.profiles.contains(where: { $0.id == id }) { profileID = nil; load() }
                    }
                }
                Spacer()
                savedLabel
                Button(String(localized: "保存配置")) { saveProfile() }.disabled(profileDraft?.isValid != true)
                if let id = profileDraft?.id, monitor.enabledProfileIDs.contains(id) {
                    Button(String(localized: "禁用此配置")) { monitor.disableProfile(id) }
                } else {
                    Button(String(localized: "保存并启用")) { if saveProfile(), let id = profileDraft?.id { monitor.enableProfile(id) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(profileDraft?.isValid != true || profileDraft?.effectiveTargetBundleIDs.isEmpty != false || !monitor.isRunning)
                }
            }
        }.padding(.horizontal, 16).padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "当前设备或配置的编辑操作"))
    }

    private var savedLabel: some View {
        Group {
            if dirty { Text(String(localized: "未保存")).foregroundStyle(.orange) }
            else if saved { Text(String(localized: "已保存")).foregroundStyle(.secondary) }
        }.font(.caption)
    }
    private func activeName(_ id: PenIdentity) -> String {
        monitor.profiles.first { $0.device == id && monitor.enabledProfileIDs.contains($0.id) }.map { String(localized: "已启用 · \($0.name)") } ?? String(localized: "未启用映射")
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
        let profile = PressureProfile(name: String(localized: "配置 \(profiles.count+1)"), device: identity, applicationRules: [])
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
