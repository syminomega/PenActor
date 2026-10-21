import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = PenMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) { monitor.start() }
    func applicationWillTerminate(_ notification: Notification) { monitor.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct PenActorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("PenActor", id: "debug") {
            ContentView(monitor: delegate.monitor)
        }
        .defaultSize(width: 1120, height: 1000)
        .commands {
            CommandGroup(replacing: .newItem) { }
            MonitorCommands(monitor: delegate.monitor)
        }
    }
}

private struct MonitorCommands: Commands {
    @ObservedObject var monitor: PenMonitor

    var body: some Commands {
        CommandMenu("监听") {
            Button("暂停全部映射") { monitor.pauseMapping() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button(monitor.isRunning ? "停止监听" : "开始监听") {
                if monitor.isRunning { monitor.stop() }
                else { monitor.start() }
            }.keyboardShortcut("p", modifiers: [.command, .shift])
        }
    }
}
