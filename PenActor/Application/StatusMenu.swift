import SwiftUI
import AppKit

struct StatusMenu: View {
    @ObservedObject var monitor: PenMonitor
    let open: (PreferencesSection?) -> Void
    var body: some View {
        Text(monitor.isRunning ? String(localized: "PenActor · 输入服务运行中") : String(localized: "PenActor · 服务已停止"))
        Text(monitor.mapping.isRunning ? String(localized: "映射已启用") : String(localized: "映射已暂停"))
        Divider()
        Button(String(localized: "设置…")) { open(nil) }.keyboardShortcut(",")
        Button(String(localized: "实时调试…")) { open(.debug) }
        Button(String(localized: "笔迹测试…")) { open(.testing) }
        Divider()
        Button(String(localized: "暂停全部映射")) { monitor.pauseMapping() }.keyboardShortcut("r", modifiers: [.command, .shift])
        Button(monitor.isRunning ? String(localized: "停止输入服务") : String(localized: "启动输入服务")) {
            if monitor.isRunning { monitor.stop() } else { monitor.start() }
        }.keyboardShortcut("p", modifiers: [.command, .shift])
        Divider()
        Button(String(localized: "退出 PenActor")) { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
