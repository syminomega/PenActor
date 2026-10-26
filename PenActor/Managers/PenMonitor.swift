import AppKit
import Combine
import CoreGraphics
import UniformTypeIdentifiers

/// Main-actor coordinator for observation, configuration, permissions, and UI snapshots.
@MainActor
final class PenMonitor: ObservableObject {
    @Published private(set) var snapshot = PenStore()
    @Published private(set) var pencilInteractions = PencilInteractionStats()
    @Published private(set) var isRunning = false
    @Published private(set) var installation = MonitorInstallation(local: false, global: false)
    @Published private(set) var listenAccess = false
    @Published private(set) var receivedLocal = false
    @Published private(set) var receivedGlobal = false
    @Published var alwaysOnTop = false
    @Published private(set) var automaticallySwitchDevices: Bool
    @Published private(set) var clearGeneration = 0
    @Published private(set) var isExporting = false
    @Published private(set) var lastExportURL: URL?
    @Published var exportError: String?
    @Published private(set) var profiles: [PressureProfile] = []
    @Published private(set) var enabledProfileIDs: Set<UUID> = []
    @Published private(set) var mapping = MappingSnapshot()
    @Published private(set) var accessibilityAccess = false
    @Published var profileError: String?
    @Published private(set) var mappingDefaults = MappingDefaults()
    @Published private(set) var startMonitoringOnLaunch: Bool
    @Published private(set) var showSettingsOnLaunch: Bool
    private var configurationPersistenceBlocked = false
    private let defaultsRepository: MappingDefaultsRepository
    private let profileRepository: PressureProfileRepository
    private let remapping = PressureRemappingEngine()
    private let workspaceObservers = WorkspaceObserverTokens()
    private var store = PenStore()
    private var interactions = PencilInteractionStats()
    private var dirty = false
    private var pendingReceivedLocal = false
    private var pendingReceivedGlobal = false
    private var timer: Timer?
    private let backend: any EventMonitoring
    private let accessCheck: () -> Bool
    private let preferences: UserDefaults
    private let privacySettings: PrivacySettingsNavigator
    @Published private(set) var permissionError: String?
    static let automaticSwitchingPreference = "automaticallySwitchDevices"

    init(backend: any EventMonitoring = AppKitEventBackend(), accessCheck: @escaping () -> Bool = {
        CGPreflightListenEventAccess()
    }, preferences: UserDefaults = .standard, profileRepository: PressureProfileRepository = PressureProfileRepository(), defaultsRepository: MappingDefaultsRepository? = nil, privacySettings: PrivacySettingsNavigator = PrivacySettingsNavigator()) {
        self.profileRepository = profileRepository
        self.privacySettings = privacySettings
        preferences.removeObject(forKey: "touchBlockingTargets")
        // Custom profile repositories (fixtures / isolated installs) receive an equally isolated defaults file.
        self.defaultsRepository = defaultsRepository ?? MappingDefaultsRepository(url: profileRepository.url.deletingLastPathComponent().appending(path: "defaults.json"))
        startMonitoringOnLaunch = preferences.object(forKey: "startMonitoringOnLaunch") as? Bool ?? true
        showSettingsOnLaunch = preferences.object(forKey: "showSettingsOnLaunch") as? Bool ?? true
        self.backend = backend
        self.accessCheck = accessCheck
        self.preferences = preferences
        let automatic = preferences.object(forKey: Self.automaticSwitchingPreference) as? Bool ?? true
        automaticallySwitchDevices = automatic
        store.automaticallySwitchDevices = automatic
        refreshPermission()
        var profileFileNeedsUpgrade = false
        do {
            profiles = try profileRepository.load()
            profileFileNeedsUpgrade = try profileRepository.needsUpgrade()
        }
        catch { configurationPersistenceBlocked = true; profileError = String(localized: "Could not load profiles. The original file was preserved: \(error.localizedDescription)") }
        do { mappingDefaults = try self.defaultsRepository.load() }
        catch { configurationPersistenceBlocked = true; profileError = String(localized: "Could not load defaults. The original file was preserved: \(error.localizedDescription)") }
        if !configurationPersistenceBlocked {
            let migrated = mappingDefaults.migrating(profiles)
            if profileFileNeedsUpgrade || migrated.defaults != mappingDefaults || migrated.profiles != profiles {
                do {
                    try backupLegacyConfiguration()
                    try self.defaultsRepository.save(migrated.defaults)
                    try profileRepository.save(migrated.profiles)
                    mappingDefaults = migrated.defaults; profiles = migrated.profiles
                } catch {
                    configurationPersistenceBlocked = true
                    profileError = String(localized: "Configuration migration did not finish. Saving and mapping are blocked. Check the original files and Backups: \(error.localizedDescription)")
                }
            }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.tokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateMappingSettings() }
            })
        }
    }

    func start() {
        guard !isRunning else { return }
        refreshPermission()
        receivedLocal = false
        receivedGlobal = false
        pendingReceivedLocal = false
        pendingReceivedGlobal = false
        installation = backend.start { [weak self] event, source in
            guard let self else { return }
            if event.type == .changeMode {
                if source == .local { self.recordPencilDoubleTap(source: .appKit) }
                return
            }
            guard TabletEventKind.classify(event) != .ignored else { return }
            let foreground = NSWorkspace.shared.frontmostApplication
            guard let decoded = PenEventDecoder.decode(
                event, source: source,
                foregroundApp: foreground?.localizedName ?? String(localized: "Unknown"),
                foregroundBundleID: foreground?.bundleIdentifier
            ) else { return }
            self.store.ingest(decoded)
            if source == .local { self.pendingReceivedLocal = true }
            else { self.pendingReceivedGlobal = true }
            self.dirty = true
        }
        isRunning = installation.local || installation.global
        if isRunning {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.publish() }
            }
            if let timer { RunLoop.main.add(timer, forMode: .common) }
        }
    }

    func stop() {
        pauseMapping()
        interruptPencilInteraction()
        backend.stop()
        timer?.invalidate()
        timer = nil
        publish()
        isRunning = false
        installation = MonitorInstallation(local: false, global: false)
    }

    func publish() {
        let latestMapping = remapping.snapshot()
        if mapping != latestMapping { mapping = latestMapping }
        if !mapping.isRunning && !mapping.isStarting && !enabledProfileIDs.isEmpty {
            enabledProfileIDs = []
            updateMappingSettings()
            mapping = remapping.snapshot()
        }
        guard dirty else { return }
        snapshot = store
        pencilInteractions = interactions
        receivedLocal = pendingReceivedLocal
        receivedGlobal = pendingReceivedGlobal
        dirty = false
    }

    func selectDevice(_ identity: PenIdentity?) {
        store.selectedIdentity = identity
        snapshot = store
    }

    func setAutomaticSwitching(_ enabled: Bool) {
        automaticallySwitchDevices = enabled
        preferences.set(enabled, forKey: Self.automaticSwitchingPreference)
        store.setAutomaticSwitching(enabled)
        snapshot = store
    }

    func clear() {
        remapping.clearDiagnostics()
        mapping = remapping.snapshot()
        store.clear()
        snapshot = store
        interactions = PencilInteractionStats()
        pencilInteractions = interactions
        dirty = false
        receivedLocal = false
        receivedGlobal = false
        pendingReceivedLocal = false
        pendingReceivedGlobal = false
        clearGeneration += 1
    }

    func makeLogDocument(exportedAt: Date = Date()) -> PenLogDocument {
        // Use the capture buffer, including events not yet published by the 60 Hz timer.
        var mapping = remapping.snapshot()
        mapping.defaults = mappingDefaults
        return PenLogDocument(store: store, interactions: interactions, isMonitoring: isRunning, exportedAt: exportedAt, profiles: profiles, mapping: mapping)
    }

    func exportLog() {
        guard !isExporting else { return }
        let data: Data
        do { data = try makeLogDocument().jsonData() }
        catch { exportError = error.localizedDescription; return }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PenActor-\(formatter.string(from: Date())).json"
        panel.title = String(localized: "Export Event Log")
        panel.message = String(localized: "Save a snapshot of the latest 500 events across all devices, captured when Export was clicked. Includes device IDs and app context.")
        isExporting = true
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.isExporting = false
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                self.lastExportURL = url
            } catch { self.exportError = error.localizedDescription }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }

    func recordPencilDoubleTap(source: PencilDoubleTapSource,
                              uptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
                              date: Date = Date()) {
        guard isRunning else { return }
        interactions.doubleTap(source: source, uptime: uptime, date: date)
        dirty = true
    }

    func recordPencilSqueeze(_ status: PencilSqueezeStatus, date: Date = Date()) {
        guard isRunning else { return }
        interactions.squeeze(status, date: date)
        dirty = true
    }

    func interruptPencilInteraction() {
        interactions.interrupt(date: Date())
        dirty = true
    }

    func refreshPermission() {
        listenAccess = accessCheck()
        accessibilityAccess = AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityAccess = AXIsProcessTrustedWithOptions(options)
        openPrivacySettings(.accessibility)
    }

    @discardableResult func saveProfile(_ profile: PressureProfile) -> Bool {
        var updated = profiles
        if let i = updated.firstIndex(where: { $0.id == profile.id }) { updated[i] = profile }
        else { updated.append(profile) }
        return saveConfiguration(profiles: updated, defaults: mappingDefaults)
    }

    func deleteProfile(_ id: UUID) {
        let updated = profiles.filter { $0.id != id }
        if saveConfiguration(profiles: updated, defaults: mappingDefaults) { disableProfile(id) }
    }

    func enableProfile(_ id: UUID) {
        refreshPermission()
        guard isRunning, let profile = profiles.first(where: { $0.id == id }), profile.isValid, !profile.effectiveTargetBundleIDs.isEmpty, !configurationPersistenceBlocked else { return }
        guard accessibilityAccess else { profileError = String(localized: "Allow Accessibility access, then recheck and enable the profile."); return }
        enabledProfileIDs.subtract(profiles.filter { $0.device == profile.device }.map(\.id))
        enabledProfileIDs.insert(id)
        updateMappingSettings()
        remapping.start()
        mapping = remapping.snapshot()
    }

    func disableProfile(_ id: UUID) {
        enabledProfileIDs.remove(id)
        if enabledProfileIDs.isEmpty { pauseMapping() }
        else { updateMappingSettings() }
    }

    func pauseMapping() {
        enabledProfileIDs = []
        remapping.stop()
        mapping = remapping.snapshot()
    }

    @discardableResult func saveDefaults(_ value: MappingDefaults) -> Bool {
        saveConfiguration(profiles: profiles, defaults: value)
    }

    @discardableResult func saveDeviceSettings(_ settings: DevicePressureDefaults) -> Bool {
        var defaults = mappingDefaults
        if let i = defaults.devices.firstIndex(where: { $0.device == settings.device }) { defaults.devices[i] = settings }
        else { defaults.devices.append(settings) }
        return saveDefaults(defaults)
    }

    func deviceDisplayName(_ identity: PenIdentity) -> String {
        let name = mappingDefaults.settings(for: identity).name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        if let observed = snapshot.devices.first(where: { $0.id == identity }) { return observed.title }
        switch identity.level {
        case .model: return String(localized: "Pen · Model group")
        case .uniqueTool, .serialNumber: return String(localized: "Pen · Saved device")
        case .session: return String(localized: "Pen · Temporary session")
        }
    }

    private func saveConfiguration(profiles updated: [PressureProfile], defaults: MappingDefaults) -> Bool {
        guard !configurationPersistenceBlocked else { return false }
        let migrated = defaults.migrating(updated)
        do {
            // Both files are validated before either write. Defaults first makes interrupted migrations repeatable.
            guard migrated.defaults.isValid, migrated.profiles.count <= 256,
                  Set(migrated.profiles.map(\.id)).count == migrated.profiles.count,
                  migrated.profiles.allSatisfy(\.isValid) else { throw CocoaError(.fileWriteInvalidFileName) }
            try defaultsRepository.save(migrated.defaults)
            try profileRepository.save(migrated.profiles)
            profiles = migrated.profiles; mappingDefaults = migrated.defaults
            profileError = nil; updateMappingSettings(); return true
        } catch { profileError = String(localized: "Could not save configuration: \(error.localizedDescription)"); return false }
    }

    private func backupLegacyConfiguration() throws {
        let files = [profileRepository.url, defaultsRepository.url].filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !files.isEmpty else { return }
        let folder = profileRepository.url.deletingLastPathComponent()
            .appending(path: "Backups/device-scoped-"+UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in files { try FileManager.default.copyItem(at: file, to: folder.appending(path: file.lastPathComponent)) }
    }

    func setStartMonitoringOnLaunch(_ value: Bool) {
        startMonitoringOnLaunch = value; preferences.set(value, forKey: "startMonitoringOnLaunch")
    }
    func setShowSettingsOnLaunch(_ value: Bool) {
        showSettingsOnLaunch = value; preferences.set(value, forKey: "showSettingsOnLaunch")
    }

    private func updateMappingSettings() {
        var applications: [Int32: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier { applications[app.processIdentifier] = id }
        }
        remapping.update(profiles: profiles.filter { enabledProfileIDs.contains($0.id) }, applications: applications, defaults: mappingDefaults)
    }

    func requestPermission() {
        _ = CGRequestListenEventAccess()
        refreshPermission()
        // A previous denial may prevent the system request from showing another prompt.
        openPrivacySettings(.inputMonitoring)
    }

    private func openPrivacySettings(_ pane: PrivacySettingsPane) {
        permissionError = privacySettings.open(pane) ? nil : String(localized: "Could not open System Settings. Go to System Settings → Privacy & Security → \(pane.title) and allow PenActor.")
    }

    func recheck() {
        let wasRunning = isRunning
        if wasRunning { stop() }
        refreshPermission()
        if wasRunning { start() }
    }
}

// The token owner removes observers even for short-lived fixture monitors.
private final class WorkspaceObserverTokens {
    var tokens: [NSObjectProtocol] = []
    deinit { for token in tokens { NSWorkspace.shared.notificationCenter.removeObserver(token) } }
}
