import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = PenMonitor()
    lazy var preferences = PreferencesWindowController(monitor: monitor)
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if monitor.startMonitoringOnLaunch { monitor.start() }
        if monitor.showSettingsOnLaunch && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            preferences.open(.general)
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
        MenuBarExtra("PenActor", systemImage: "pencil.tip.crop.circle") {
            StatusMenu(monitor: delegate.monitor) { delegate.preferences.open($0) }
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
