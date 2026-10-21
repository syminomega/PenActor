import AppKit
import SwiftUI

enum PreferencesSection: Int, CaseIterable {
    case general, applications, hardware, debug, testing
    var title: String { ["通用", "应用", "硬件", "调试", "测试"][rawValue] }
    var symbol: String { ["slider.horizontal.3", "app", "pencil.tip", "waveform.path.ecg", "scribble.variable"][rawValue] }
}

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let tabs = NSTabViewController()
    private let monitor: PenMonitor
    init(monitor: PenMonitor) {
        self.monitor = monitor
        tabs.tabStyle = .toolbar
        for section in PreferencesSection.allCases {
            let host = NSHostingController(rootView: ContentView(monitor: monitor, section: section))
            let item = NSTabViewItem(viewController: host)
            item.label = section.title
            item.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: section.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.title = "PenActor 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1040, height: 760))
        window.minSize = NSSize(width: 980, height: 710)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("PenActorPreferences")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func open(_ section: PreferencesSection? = nil) {
        if let section { tabs.selectedTabViewItemIndex = section.rawValue }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        monitor.refreshPermission()
    }
    func windowDidBecomeKey(_ notification: Notification) { monitor.refreshPermission() }
    func windowWillClose(_ notification: Notification) { monitor.interruptPencilInteraction() }
}
