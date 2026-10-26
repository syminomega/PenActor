import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var isTesting: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
    lazy var monitor: PenMonitor = {
        if isTesting {
            // Test hosts must never migrate the real user's configuration files.
            let url = FileManager.default.temporaryDirectory.appending(path: "PenActorTestHost-"+UUID().uuidString+"/profiles.json")
            return PenMonitor(profileRepository: PressureProfileRepository(url: url))
        }
        LegacyPreferencesMigration.migrate(
            legacy: UserDefaults.standard.persistentDomain(forName: "dev.penactor.PenActor") ?? [:],
            into: .standard)
        return PenMonitor()
    }()
    lazy var preferences = PreferencesWindowController(monitor: monitor)
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard !isTesting else { return }
        if monitor.startMonitoringOnLaunch { monitor.start() }
        if monitor.showSettingsOnLaunch {
            preferences.open(.profiles)
        }
    }
    func applicationWillTerminate(_ notification: Notification) { monitor.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        preferences.open(); return true
    }
}
