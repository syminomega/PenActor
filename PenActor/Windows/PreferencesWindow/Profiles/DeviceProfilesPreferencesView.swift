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
                Text(String(localized: "Device")).font(.headline).padding(16)
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
                        PreferencesPageHeader(title: monitor.deviceDisplayName(selected), subtitle: String(localized: "Set this device’s pressure defaults, then add target apps to a profile. Override settings only when needed."))
                        HStack {
                            TextField(String(localized: "Device name (leave blank for system name)"), text: Binding(get: { deviceDraft?.name ?? "" }, set: { draft.setDeviceName($0, for: selected); changed() }))
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .deviceName)
                            Button(String(localized: "Save Name")) { saveName() }.disabled(deviceDraft?.isValid != true || selected.level == .session)
                        }
                        DisclosureGroup(String(localized: "Device identity · \(selected.level.label)")) {
                            Text(selected.key).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            if selected.level == .model {
                                Text(String(localized: "This identity groups pens by model and cannot distinguish identical pens. Renaming does not change matching.")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if selected.level == .session {
                            Text(String(localized: "Hardware proximity metadata is needed before settings can be saved. Move the pen out of range and back in.")).foregroundStyle(.secondary)
                        } else {
                            HStack {
                                Picker(String(localized: "Edit"), selection: Binding(get: { profileID }, set: { requestProfile($0) })) {
                                    Text(String(localized: "Device defaults")).tag(UUID?.none)
                                    ForEach(profiles) { Text($0.name).tag(Optional($0.id)) }
                                }
                                Button(String(localized: "New Profile")) { create(selected) }.disabled(dirty)
                            }
                            if profileID == nil { deviceEditor }
                            else if profileDraft != nil { profileEditor.id(profileID) }
                        }
                    } else {
                        PreferencesPageHeader(title: String(localized: "Profiles"), subtitle: String(localized: "Configure each device separately. Apps in a profile inherit that device’s defaults."))
                        ContentUnavailableView(String(localized: "Waiting for a pen"), systemImage: "pencil.tip", description: Text(String(localized: "Connect Sidecar or a tablet, bring the pen into range, and draw. Saved devices remain in the sidebar.")))
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
        .confirmationDialog(String(localized: "Discard unsaved changes?"), isPresented: $confirmDiscard) {
            Button(String(localized: "Discard Changes"), role: .destructive) {
                if switchingDevice { selected = pendingDevice; profileID = nil }
                else { profileID = pendingProfile }
                load()
            }
            Button(String(localized: "Keep Editing"), role: .cancel) { }
        } message: { Text(String(localized: "Switching loads the saved device settings or profile.")) }
    }
    private var deviceEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox(String(localized: "Default pressure settings")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(localized: "These curve and taper settings belong only to this device and are shared by apps that inherit them."))
                        .font(.caption).foregroundStyle(.secondary)
                    PressureConfigurationEditor(configuration: Binding(get: { deviceDraft?.configuration ?? PressureConfiguration() }, set: { deviceDraft?.configuration = $0; changed() }))
                }.padding(10)
            }
            Text(String(localized: "Device defaults do not enable mapping. Add a profile and target apps.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var profileEditor: some View {
        let editingProfileID = profileDraft?.id
        return VStack(alignment: .leading, spacing: 12) {
            TextField(String(localized: "Profile name"), text: Binding(get: { profileDraft?.name ?? "" }, set: { draft.setProfileName($0, for: editingProfileID); changed() }))
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .profileName)
            GroupBox(String(localized: "Target apps")) {
                VStack(alignment: .leading, spacing: 0) {
                    if profileDraft?.applicationRules?.isEmpty != false {
                        Text(String(localized: "Add target apps. Each inherits this device’s pressure settings by default.")).foregroundStyle(.secondary).padding(10)
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
            Text(String(localized: "Inherited settings follow device defaults. Overrides affect only this app in this profile. Unlisted apps pass through."))
                .font(.caption).foregroundStyle(.secondary)
            Text(String(localized: "Enable one profile per device; devices work independently. Saved settings apply from the next stroke. Disabling or pausing stops changes immediately. Bring the pen back into range after first enabling."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var editingActions: some View {
        HStack {
            if profileID == nil {
                Text(String(localized: "Device default settings")).font(.caption).foregroundStyle(.secondary)
                savedLabel
                Spacer()
                Button(String(localized: "Save Defaults")) { saveDevice() }.buttonStyle(.borderedProminent).disabled(deviceDraft?.isValid != true)
            } else {
                Button(String(localized: "Delete Profile"), role: .destructive) {
                    if let id = profileDraft?.id {
                        monitor.deleteProfile(id)
                        if !monitor.profiles.contains(where: { $0.id == id }) { profileID = nil; load() }
                    }
                }
                Spacer()
                savedLabel
                Button(String(localized: "Save Profile")) { saveProfile() }.disabled(profileDraft?.isValid != true)
                if let id = profileDraft?.id, monitor.enabledProfileIDs.contains(id) {
                    Button(String(localized: "Disable Profile")) { monitor.disableProfile(id) }
                } else {
                    Button(String(localized: "Save and Enable")) { if saveProfile(), let id = profileDraft?.id { monitor.enableProfile(id) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(profileDraft?.isValid != true || profileDraft?.effectiveTargetBundleIDs.isEmpty != false || !monitor.isRunning)
                }
            }
        }.padding(.horizontal, 16).padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Editing actions for the selected device or profile"))
    }

    private var savedLabel: some View {
        Group {
            if dirty { Text(String(localized: "Unsaved")).foregroundStyle(.orange) }
            else if saved { Text(String(localized: "Saved")).foregroundStyle(.secondary) }
        }.font(.caption)
    }
    private func activeName(_ id: PenIdentity) -> String {
        monitor.profiles.first { $0.device == id && monitor.enabledProfileIDs.contains($0.id) }.map { String(localized: "Enabled · \($0.name)") } ?? String(localized: "Mapping disabled")
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
        let profile = PressureProfile(name: String(localized: "Profile \(profiles.count+1)"), device: identity, applicationRules: [])
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
