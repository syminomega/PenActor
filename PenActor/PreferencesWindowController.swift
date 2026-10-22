import AppKit
import SwiftUI

enum PreferencesSection: Int, CaseIterable {
    case general, profiles, debug, testing
    var title: String { ["通用", "配置", "调试", "测试"][rawValue] }
    var defaultSize: NSSize {
        switch self {
        case .general: NSSize(width: 860, height: 410)
        case .profiles: NSSize(width: 860, height: 600)
        case .debug: NSSize(width: 860, height: 600)
        case .testing: NSSize(width: 860, height: 620)
        }
    }
    var minimumSize: NSSize {
        switch self {
        case .general: NSSize(width: 820, height: 350)
        case .profiles: NSSize(width: 820, height: 500)
        case .debug: NSSize(width: 820, height: 500)
        case .testing: NSSize(width: 820, height: 500)
        }
    }
    var symbol: String { ["slider.horizontal.3", "slider.horizontal.2.square", "waveform.path.ecg", "scribble.variable"][rawValue] }
}

@MainActor
private final class PreferencesWindow: NSWindow {
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0.2 }
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
private final class PreferencesSizingRelay {
    var report: ((PreferencesSection, CGFloat) -> Void)?
}

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let tabs = PreferencesTabController()
    private var activeSection = PreferencesSection.profiles
    private var heights: [PreferencesSection: CGFloat] = [:]
    private let monitor: PenMonitor
    private var measuredHeights: [PreferencesSection: CGFloat] = [:]
    private let sizing = PreferencesSizingRelay()
    init(monitor: PenMonitor) {
        self.monitor = monitor
        tabs.tabStyle = .toolbar
        for section in PreferencesSection.allCases {
            let relay = sizing
            let host = NSHostingController(rootView: ContentView(monitor: monitor, section: section, onContentHeightChange: { [weak relay] height in
                relay?.report?(section, height)
            }))
            host.sizingOptions = []
            host.title = "PenActor · \(section.title)"
            let item = NSTabViewItem(viewController: host)
            item.label = section.title
            item.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: section.title)
            tabs.addTabViewItem(item)
        }
        tabs.selectedTabViewItemIndex = PreferencesSection.profiles.rawValue
        let window = PreferencesWindow(contentViewController: tabs)
        window.title = "PenActor 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(PreferencesSection.profiles.defaultSize)
        window.titleVisibility = .visible
        window.contentMinSize = PreferencesSection.profiles.minimumSize
        window.isReleasedWhenClosed = false
        super.init(window: window)
        sizing.report = { [weak self] section, height in
            // Defer window mutations until SwiftUI has finished the current layout pass.
            DispatchQueue.main.async { [weak self] in
                guard let self, abs((self.measuredHeights[section] ?? 0) - height) > 1 else { return }
                self.measuredHeights[section] = height
                if self.activeSection == section { self.resize(for: section, rememberingPrevious: false) }
            }
        }
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
            heights[activeSection] = window.contentRect(forFrameRect: window.frame).height
        }
        activeSection = section
        guard !window.isZoomed else { window.contentMinSize = section.minimumSize; return }
        let currentContent = window.contentRect(forFrameRect: window.frame).size
        // Avoid a minimum-height constraint forcing an instant jump before the animation expands.
        window.contentMinSize = NSSize(width: section.minimumSize.width, height: min(currentContent.height, section.minimumSize.height))
        let content = NSSize(width: currentContent.width, height: fittedHeight(for: section) ?? heights[section] ?? section.defaultSize.height)
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY-frame.height)
        if let visible = window.screen?.visibleFrame {
            frame.size.height = min(frame.height, visible.height)
            frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY-frame.height))
        }
        let animate = window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.setFrame(frame, display: true, animate: animate)
        window.contentMinSize = NSSize(width: section.minimumSize.width, height: fittedHeight(for: section) == nil ? section.minimumSize.height : min(content.height, window.contentRect(forFrameRect: window.frame).height))
    }

    private func fittedHeight(for section: PreferencesSection) -> CGFloat? {
        guard let height = measuredHeights[section], let window else { return nil }
        let chrome = max(0, window.contentRect(forFrameRect: window.frame).height - window.contentLayoutRect.height)
        return max(section.minimumSize.height, height + chrome)
    }

    func windowDidBecomeKey(_ notification: Notification) { monitor.refreshPermission() }
    func windowWillClose(_ notification: Notification) { monitor.interruptPencilInteraction() }
}
