import AppKit
import SwiftUI

enum PreferencesSection: Int, CaseIterable {
    case general, profiles, debug, testing
    var title: String { ["通用", "配置", "调试", "测试"][rawValue] }
    var defaultSize: NSSize {
        switch self {
        case .general: NSSize(width: 620, height: 410)
        case .profiles: NSSize(width: 860, height: 600)
        case .debug: NSSize(width: 900, height: 600)
        case .testing: NSSize(width: 860, height: 620)
        }
    }
    var minimumSize: NSSize {
        switch self {
        case .general: NSSize(width: 560, height: 350)
        case .profiles: NSSize(width: 800, height: 500)
        case .debug: NSSize(width: 820, height: 500)
        case .testing: NSSize(width: 760, height: 500)
        }
    }
    var symbol: String { ["slider.horizontal.3", "slider.horizontal.2.square", "waveform.path.ecg", "scribble.variable"][rawValue] }
}

@MainActor
private final class PreferencesTabController: NSTabViewController {
    var onSelection: ((Int) -> Void)?
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        onSelection?(selectedTabViewItemIndex)
    }
}

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let tabs = PreferencesTabController()
    private var activeSection = PreferencesSection.profiles
    private var sizes: [PreferencesSection: NSSize] = [:]
    private let monitor: PenMonitor
    init(monitor: PenMonitor) {
        self.monitor = monitor
        tabs.tabStyle = .toolbar
        for section in PreferencesSection.allCases {
            let host = NSHostingController(rootView: ContentView(monitor: monitor, section: section))
            host.sizingOptions = []
            host.title = "PenActor · \(section.title)"
            let item = NSTabViewItem(viewController: host)
            item.label = section.title
            item.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: section.title)
            tabs.addTabViewItem(item)
        }
        tabs.selectedTabViewItemIndex = PreferencesSection.profiles.rawValue
        let window = NSWindow(contentViewController: tabs)
        window.title = "PenActor 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(PreferencesSection.profiles.defaultSize)
        window.titleVisibility = .visible
        window.contentMinSize = PreferencesSection.profiles.minimumSize
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("PenActorCompactPreferences")
        resize(for: .profiles, rememberingPrevious: false)
        tabs.onSelection = { [weak self] index in
            guard let section = PreferencesSection(rawValue: index) else { return }
            self?.resize(for: section, rememberingPrevious: true)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func open(_ section: PreferencesSection? = nil) {
        if let section { tabs.selectedTabViewItemIndex = section.rawValue }
        window?.title = "PenActor 设置"
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        monitor.refreshPermission()
    }
    private func resize(for section: PreferencesSection, rememberingPrevious: Bool) {
        guard let window else { return }
        guard section != activeSection || !rememberingPrevious else { return }
        if rememberingPrevious, section != activeSection {
            sizes[activeSection] = window.contentRect(forFrameRect: window.frame).size
        }
        activeSection = section
        window.contentMinSize = section.minimumSize
        guard !window.isZoomed else { return }
        let content = sizes[section] ?? section.defaultSize
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY-frame.height)
        if let visible = window.screen?.visibleFrame {
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX-frame.width))
            frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY-frame.height))
        }
        window.setFrame(frame, display: true)
    }

    func windowDidBecomeKey(_ notification: Notification) { monitor.refreshPermission() }
    func windowWillClose(_ notification: Notification) { monitor.interruptPencilInteraction() }
}
