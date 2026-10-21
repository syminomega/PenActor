import AppKit
import Combine
import CoreGraphics
import UniformTypeIdentifiers

struct MonitorInstallation {
    let local: Bool
    let global: Bool
}

@MainActor
protocol EventMonitoring: AnyObject {
    func start(handler: @escaping @MainActor (NSEvent, EventSource) -> Void) -> MonitorInstallation
    func stop()
}

@MainActor
final class AppKitEventBackend: EventMonitoring {
    private var localToken: Any?
    private var globalToken: Any?

    func start(handler: @escaping @MainActor (NSEvent, EventSource) -> Void) -> MonitorInstallation {
        stop()
        let mask: NSEvent.EventTypeMask = [
            .tabletPoint, .tabletProximity, .mouseMoved,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged
        ]
        // AppKit documents both monitor callbacks as main-thread callbacks.
        localToken = NSEvent.addLocalMonitorForEvents(matching: mask.union(.changeMode)) { event in
            MainActor.assumeIsolated { handler(event, .local) }
            return event
        }
        globalToken = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            MainActor.assumeIsolated { handler(event, .global) }
        }
        return MonitorInstallation(local: localToken != nil, global: globalToken != nil)
    }

    func stop() {
        if let localToken { NSEvent.removeMonitor(localToken) }
        if let globalToken { NSEvent.removeMonitor(globalToken) }
        localToken = nil
        globalToken = nil
    }
}

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
    static let automaticSwitchingPreference = "automaticallySwitchDevices"

    init(backend: any EventMonitoring = AppKitEventBackend(), accessCheck: @escaping () -> Bool = {
        CGPreflightListenEventAccess()
    }, preferences: UserDefaults = .standard, profileRepository: PressureProfileRepository = PressureProfileRepository(), defaultsRepository: MappingDefaultsRepository? = nil) {
        self.profileRepository = profileRepository
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
        do { profiles = try profileRepository.load() }
        catch { profileError = "配置读取失败，未覆盖原文件：\(error.localizedDescription)" }
        do { mappingDefaults = try self.defaultsRepository.load() }
        catch { profileError = "默认设置读取失败，未覆盖原文件：\(error.localizedDescription)" }
        registerLegacyApplications()
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
                foregroundApp: foreground?.localizedName ?? "未知",
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
        panel.title = "导出事件日志"
        panel.message = "保存点击导出时的全部设备最近 500 条事件快照；包含设备标识和应用上下文。"
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
    }

    @discardableResult func saveProfile(_ profile: PressureProfile) -> Bool {
        var updated = profiles
        if let i = updated.firstIndex(where: { $0.id == profile.id }) { updated[i] = profile }
        else { updated.append(profile) }
        do { try profileRepository.save(updated); profiles = updated; profileError = nil; updateMappingSettings(); return true }
        catch { profileError = "保存失败：\(error.localizedDescription)"; return false }
    }

    func deleteProfile(_ id: UUID) {
        let updated = profiles.filter { $0.id != id }
        do { try profileRepository.save(updated); profiles = updated; disableProfile(id); profileError = nil }
        catch { profileError = error.localizedDescription }
    }

    func enableProfile(_ id: UUID) {
        refreshPermission()
        guard isRunning, let profile = profiles.first(where: { $0.id == id }), profile.isValid, !profile.targetBundleIDs.isEmpty else { return }
        guard accessibilityAccess else { profileError = "请允许辅助功能权限，然后重新检查并启用。"; return }
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
        do {
            try defaultsRepository.save(value)
            mappingDefaults = value; profileError = nil; updateMappingSettings(); return true
        } catch { profileError = "保存默认设置失败：\(error.localizedDescription)"; return false }
    }

    func setStartMonitoringOnLaunch(_ value: Bool) {
        startMonitoringOnLaunch = value; preferences.set(value, forKey: "startMonitoringOnLaunch")
    }
    func setShowSettingsOnLaunch(_ value: Bool) {
        showSettingsOnLaunch = value; preferences.set(value, forKey: "showSettingsOnLaunch")
    }

    private func registerLegacyApplications() {
        for id in Set(profiles.flatMap(\.targetBundleIDs)).sorted() where !mappingDefaults.applications.contains(where: { $0.bundleID == id }) {
            guard mappingDefaults.applications.count < 256 else { break }
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            let name = url?.deletingPathExtension().lastPathComponent ?? id
            mappingDefaults.applications.append(.init(bundleID: id, name: name))
        }
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
