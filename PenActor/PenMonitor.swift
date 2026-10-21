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
    }, preferences: UserDefaults = .standard) {
        self.backend = backend
        self.accessCheck = accessCheck
        self.preferences = preferences
        let automatic = preferences.object(forKey: Self.automaticSwitchingPreference) as? Bool ?? true
        automaticallySwitchDevices = automatic
        store.automaticallySwitchDevices = automatic
        refreshPermission()
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
        interruptPencilInteraction()
        backend.stop()
        timer?.invalidate()
        timer = nil
        publish()
        isRunning = false
        installation = MonitorInstallation(local: false, global: false)
    }

    func publish() {
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
        PenLogDocument(store: store, interactions: interactions, isMonitoring: isRunning, exportedAt: exportedAt)
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

    func refreshPermission() { listenAccess = accessCheck() }

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
