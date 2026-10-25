import SwiftUI
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

@main
struct PenActorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        MenuBarExtra {
            StatusMenu(monitor: delegate.monitor) { delegate.preferences.open($0) }
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .accessibilityLabel("PenActor")
        }.menuBarExtraStyle(.menu)
    }
}

private struct StatusMenu: View {
    @ObservedObject var monitor: PenMonitor
    let open: (PreferencesSection?) -> Void
    var body: some View {
        Text(monitor.isRunning ? "PenActor · 输入服务运行中" : "PenActor · 服务已停止")
        Text(monitor.mapping.isRunning ? "映射已启用" : "映射已暂停")
        Divider()
        Button("设置…") { open(nil) }.keyboardShortcut(",")
        Button("实时调试…") { open(.debug) }
        Button("笔迹测试…") { open(.testing) }
        Divider()
        Button("暂停全部映射") { monitor.pauseMapping() }.keyboardShortcut("r", modifiers: [.command, .shift])
        Button(monitor.isRunning ? "停止输入服务" : "启动输入服务") {
            if monitor.isRunning { monitor.stop() } else { monitor.start() }
        }.keyboardShortcut("p", modifiers: [.command, .shift])
        Divider()
        Button("退出 PenActor") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

/// Preserve app preferences when moving to dev.SyminStudio.PenActor; pressure JSON stays in the same folder.
enum LegacyPreferencesMigration {
    static let marker = "didMigrateLegacyBundlePreferences"
    static func migrate(legacy: [String: Any], into preferences: UserDefaults) {
        guard !preferences.bool(forKey: marker) else { return }
        for key in ["startMonitoringOnLaunch", "showSettingsOnLaunch", "automaticallySwitchDevices", "NSWindow Frame PenActorCompactPreferences"] {
            if preferences.object(forKey: key) == nil, let value = legacy[key] { preferences.set(value, forKey: key) }
        }
        preferences.set(true, forKey: marker)
    }
}
