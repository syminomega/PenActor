import AppKit
import SwiftUI
import QuartzCore

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
final class PreferencesWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private let tabs = PreferencesTabController()
    private let navigation = NSSegmentedControl(labels: PreferencesSection.allCases.map(\.title), trackingMode: .selectOne, target: nil, action: nil)
    private static let navigationItem = NSToolbarItem.Identifier("PenActorPreferencesSections")
    private var activeSection = PreferencesSection.profiles
    private var heights: [PreferencesSection: CGFloat] = [:]
    private var frameSection = PreferencesSection.profiles
    private var resizeTarget: NSRect?
    private var resizeRevision: UInt64 = 0
    private var requestRevision: UInt64 = 0
    private var completionMinimum: NSSize?
    private var pendingResize: DispatchWorkItem?
    private let monitor: PenMonitor
    private let setActivationPolicy: (NSApplication.ActivationPolicy) -> Void
    private var measuredHeights: [PreferencesSection: CGFloat] = [:]
    private let sizing = PreferencesSizingRelay()
    init(monitor: PenMonitor, setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) }) {
        self.monitor = monitor
        self.setActivationPolicy = setActivationPolicy
        tabs.tabStyle = .unspecified
        tabs.tabView.tabViewType = .noTabsNoBorder
        navigation.selectedSegment = activeSection.rawValue
        navigation.segmentStyle = .automatic
        navigation.setAccessibilityLabel("设置页面")
        for section in PreferencesSection.allCases {
            navigation.setImage(NSImage(systemSymbolName: section.symbol, accessibilityDescription: section.title), forSegment: section.rawValue)
            navigation.setImageScaling(.scaleProportionallyDown, forSegment: section.rawValue)
            navigation.setWidth(78, forSegment: section.rawValue)
        }
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
        let window = NSWindow(contentViewController: tabs)
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
        navigation.target = self
        navigation.action = #selector(selectSection(_:))
        let toolbar = NSToolbar(identifier: "PenActorCompactNavigation")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        toolbar.centeredItemIdentifiers = [Self.navigationItem]
        window.toolbarStyle = .unifiedCompact
        window.toolbar = toolbar
        window.center()
        window.setFrameAutosaveName("PenActorCompactPreferences")
        resize(for: .profiles, rememberingPrevious: false)
        tabs.onSelection = { [weak self] index in
            guard let self, let section = PreferencesSection(rawValue: index) else { return }
            // A click already selected the segment; don't restart its native highlight animation.
            if self.navigation.selectedSegment != index { self.navigation.selectedSegment = index }
            self.window?.makeFirstResponder(nil)
            self.resize(for: section, rememberingPrevious: true)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func open(_ section: PreferencesSection? = nil) {
        // Keep LSUIElement for background launches, but expose Dock / Cmd-Tab while settings are open.
        setActivationPolicy(.regular)
        if let section { tabs.selectedTabViewItemIndex = section.rawValue }
        window?.title = "PenActor 设置"
        showWindow(nil)
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        monitor.refreshPermission()
    }
    @objc private func selectSection(_ sender: NSSegmentedControl) {
        guard PreferencesSection(rawValue: sender.selectedSegment) != nil else { return }
        window?.makeFirstResponder(nil)
        tabs.selectedTabViewItemIndex = sender.selectedSegment
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [Self.navigationItem, .flexibleSpace] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [Self.navigationItem] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == Self.navigationItem else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "设置页面"; item.view = navigation
        return item
    }

    private func resize(for section: PreferencesSection, rememberingPrevious: Bool) {
        guard let window else { return }
        guard section != activeSection || !rememberingPrevious else { return }
        if rememberingPrevious, section != activeSection, frameSection == activeSection {
            // Store the intended height, not an intermediate frame or another page's frame.
            heights[activeSection] = window.contentRect(forFrameRect: resizeTarget ?? window.frame).height
        }
        activeSection = section
        pendingResize?.cancel()
        requestRevision += 1
        let requestToken = requestRevision
        if !window.isVisible {
            applyResize(for: section)
            return
        }
        // Let selection highlighting finish its event callback and coalesce initial SwiftUI measurements.
        let request = DispatchWorkItem { [weak self] in
            guard let self, self.activeSection == section, self.requestRevision == requestToken else { return }
            self.applyResize(for: section)
        }
        pendingResize = request
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(24), execute: request)
    }

    private func applyResize(for section: PreferencesSection) {
        guard let window, section == activeSection else { return }
        guard !window.isZoomed else { window.contentMinSize = section.minimumSize; return }
        let currentContent = window.contentRect(forFrameRect: window.frame).size
        let content = NSSize(width: currentContent.width, height: fittedHeight(for: section) ?? heights[section] ?? section.defaultSize.height)
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY-frame.height)
        if let visible = window.screen?.visibleFrame {
            frame.size.height = min(frame.height, visible.height)
            frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY-frame.height))
        }
        let minimumHeight = fittedHeight(for: section) == nil ? section.minimumSize.height : min(content.height, frame.height - (window.frame.height-currentContent.height))
        let minimum = NSSize(width: section.minimumSize.width, height: minimumHeight)
        frameSection = section
        completionMinimum = minimum
        if let target = resizeTarget, abs(target.height-frame.height) < 1, abs(target.width-frame.width) < 1 {
            return
        }
        if resizeTarget == nil, abs(window.frame.height-frame.height) < 1, abs(window.frame.width-frame.width) < 1 {
            window.contentMinSize = minimum
            return
        }
        resizeRevision += 1
        let revision = resizeRevision
        let animate = window.isVisible && !window.inLiveResize && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Raising this minimum before an expanding animation would jump straight to its final height.
        window.contentMinSize = NSSize(width: minimum.width, height: min(currentContent.height, minimum.height))
        if !animate {
            resizeTarget = nil
            window.setFrame(frame, display: true)
            window.contentMinSize = minimum
            return
        }
        resizeTarget = frame
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        } completionHandler: { [weak self, weak window] in
            Task { @MainActor in
                guard let self, let window, self.resizeRevision == revision else { return }
                self.resizeTarget = nil
                window.contentMinSize = self.completionMinimum ?? minimum
                self.completionMinimum = nil
            }
        }
    }

    private func fittedHeight(for section: PreferencesSection) -> CGFloat? {
        guard let height = measuredHeights[section], let window else { return nil }
        let chrome = max(0, window.contentRect(forFrameRect: window.frame).height - window.contentLayoutRect.height)
        return max(section.minimumSize.height, height + chrome)
    }

    func windowDidBecomeKey(_ notification: Notification) { monitor.refreshPermission() }
    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow, closedWindow === window else { return }
        pendingResize?.cancel()
        requestRevision += 1
        resizeRevision += 1
        resizeTarget = nil
        completionMinimum = nil
        monitor.interruptPencilInteraction()
        // Losing focus or minimizing must not remove the Dock entry; only closing settings does.
        setActivationPolicy(.accessory)
    }
}
