import SwiftUI
import AppKit

struct StatusMenu: View {
    @ObservedObject var monitor: PenMonitor
    let open: (PreferencesSection?) -> Void
    var body: some View {
        Text(monitor.isRunning ? String(localized: "PenActor · Input service running") : String(localized: "PenActor · Service stopped"))
        Text(monitor.mapping.isRunning ? String(localized: "Mapping enabled") : String(localized: "Mapping paused"))
        Divider()
        Button(String(localized: "Settings…")) { open(nil) }.keyboardShortcut(",")
        Button(String(localized: "Live Debug…")) { open(.debug) }
        Button(String(localized: "Stroke Testing…")) { open(.testing) }
        Divider()
        Button(String(localized: "Pause All Mapping")) { monitor.pauseMapping() }.keyboardShortcut("r", modifiers: [.command, .shift])
        Button(monitor.isRunning ? String(localized: "Stop Input Service") : String(localized: "Start Input Service")) {
            if monitor.isRunning { monitor.stop() } else { monitor.start() }
        }.keyboardShortcut("p", modifiers: [.command, .shift])
        Divider()
        Button(String(localized: "Quit PenActor")) { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
