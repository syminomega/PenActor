import XCTest
import AppKit
import SwiftUI
@testable import PenActor

extension PressureMappingTests {
    @MainActor func testPreferencesPersistenceExportAndClosedWindowKeepServiceAlive() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "PenActorTests."+UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let repo = PressureProfileRepository(url: root.appending(path: "profiles.json"))
        let backend = MappingPanelBackend(event: try XCTUnwrap(NSEvent(cgEvent: proximity())))
        let monitor = PenMonitor(backend: backend, preferences: preferences, profileRepository: repo)
        monitor.start(); defer { monitor.stop() }
        var defaults = MappingDefaults(); defaults.global.curve = .light
        XCTAssertTrue(monitor.saveDefaults(defaults))
        monitor.setStartMonitoringOnLaunch(false); monitor.setShowSettingsOnLaunch(false)
        let controller = PreferencesWindowController(monitor: monitor)
        let window = try XCTUnwrap(controller.window)
        let profileWidth = window.frame.width
        let tabs = try XCTUnwrap(window.contentViewController as? NSTabViewController)
        XCTAssertEqual(tabs.tabViewItems.map(\.label), [String(localized: "General"), String(localized: "Profiles"), String(localized: "Debug"), String(localized: "Testing")])
        XCTAssertEqual(tabs.selectedTabViewItemIndex, PreferencesSection.profiles.rawValue)
        tabs.selectedTabViewItemIndex = PreferencesSection.general.rawValue
        XCTAssertEqual(window.frame.width, profileWidth, accuracy: 1)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).height, PreferencesSection.general.defaultSize.height, accuracy: 1)
        XCTAssertEqual(window.contentMinSize.width, PreferencesSection.general.minimumSize.width)
        tabs.selectedTabViewItemIndex = PreferencesSection.profiles.rawValue
        XCTAssertEqual(window.frame.width, profileWidth, accuracy: 1)
        // A manual resize is retained when returning to this page.
        window.setContentSize(NSSize(width: 900, height: 640))
        for section in PreferencesSection.allCases {
            tabs.selectedTabViewItemIndex = section.rawValue
            XCTAssertEqual(window.contentRect(forFrameRect: window.frame).width, 900, accuracy: 1)
        }
        tabs.selectedTabViewItemIndex = PreferencesSection.profiles.rawValue
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).height, 640, accuracy: 1)
        window.close()
        XCTAssertTrue(monitor.isRunning)
        XCTAssertTrue(controller.window === window)
        XCTAssertFalse(AppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApp))
        let restored = PenMonitor(preferences: preferences, profileRepository: repo)
        XCTAssertFalse(restored.startMonitoringOnLaunch); XCTAssertFalse(restored.showSettingsOnLaunch)
        XCTAssertEqual(restored.mappingDefaults, defaults)
        XCTAssertTrue(restored.enabledProfileIDs.isEmpty)
        XCTAssertEqual(try monitor.makeLogDocument().mapping.defaults, defaults)
    }

    @MainActor func testEveryPreferencesPageRendersAtDefaultWindowSize() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = PressureProfileRepository(url: root.appending(path: "profiles.json"))
        let monitor = PenMonitor(profileRepository: repo)
        var p = profile(); p.taper.entryEnabled = true; p.taper.exitEnabled = true
        XCTAssertTrue(monitor.saveProfile(p))
        var defaults = MappingDefaults()
        var rule = ApplicationPressureRule(bundleID: "com.adobe.Photoshop", name: "Photoshop")
        rule.mode = .custom; rule.configuration.curve = .light
        defaults.applications = [rule]; XCTAssertTrue(monitor.saveDefaults(defaults))
        for section in PreferencesSection.allCases {
            let host = NSHostingView(rootView: ContentView(monitor: monitor, section: section).frame(width: section.defaultSize.width, height: section.defaultSize.height))
            host.frame = NSRect(origin: .zero, size: section.defaultSize)
            // Attach the hosting view to an unshown window so AppKit-backed lists can lay out.
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(filePath: "/tmp/PenActor-settings-\(section.rawValue).png"))
            XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        }
    }

    @MainActor func testDebugSectionsRenderWithHardwareDataAtCompactAndMinimumSizes() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let events = try [proximity(), point(0.5)].map { try XCTUnwrap(NSEvent(cgEvent: $0)) }
        let monitor = PenMonitor(backend: MappingPanelBackend(events: events), profileRepository: .init(url: root.appending(path: "profiles.json")))
        monitor.start(); monitor.publish(); defer { monitor.stop() }
        XCTAssertNotNil(monitor.snapshot.selectedDevice?.lastSampleEvent)
        for section: ContentView.DebugSection in [.live, .device, .events] {
            for (label, size) in [("default", PreferencesSection.debug.defaultSize), ("minimum", PreferencesSection.debug.minimumSize)] {
                let host = NSHostingView(rootView: ContentView(monitor: monitor, section: .debug, debugSection: section).frame(width: size.width, height: size.height))
                host.frame = NSRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host; host.layoutSubtreeIfNeeded()
                XCTAssertLessThanOrEqual(host.fittingSize.width, size.width+1)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(filePath: "/tmp/PenActor-debug-\(section.rawValue)-\(label).png"))
            }
        }
    }

    @MainActor func testTestingPageOnlyResizesCanvasAndHasNoScrollContainer() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let monitor = PenMonitor(profileRepository: .init(url: root.appending(path: "profiles.json")))
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        for expanded in [false, true] {
            var canvasHeights: [CGFloat] = []
            for height: CGFloat in [500, 620, 780] {
                let host = NSHostingView(rootView: ContentView(monitor: monitor, section: .testing, pencilDetailsExpanded: expanded).frame(width: 860, height: height))
                host.frame = NSRect(x: 0, y: 0, width: 860, height: height)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.contentView = host; host.layoutSubtreeIfNeeded()
                let views = descendants(host)
                XCTAssertFalse(views.contains { $0 is NSScrollView })
                let canvas = try XCTUnwrap(views.compactMap { $0 as? PenTestView }.first)
                XCTAssertGreaterThanOrEqual(canvas.bounds.height, 99)
                canvasHeights.append(canvas.bounds.height)
                XCTAssertLessThanOrEqual(host.fittingSize.height, height+1)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(filePath: "/tmp/PenActor-testing-\(Int(height))-\(expanded).png"))
            }
            XCTAssertEqual(canvasHeights[1]-canvasHeights[0], 120, accuracy: 1)
            XCTAssertEqual(canvasHeights[2]-canvasHeights[1], 160, accuracy: 1)
        }
    }

    @MainActor func testGeneralAndDebugFitContentWithoutOuterScrolling() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = MappingPanelBackend(events: [try XCTUnwrap(NSEvent(cgEvent: proximity())), try XCTUnwrap(NSEvent(cgEvent: point(0.5)))])
        let monitor = PenMonitor(backend: backend, profileRepository: .init(url: root.appending(path: "profiles.json")))
        monitor.start(); monitor.publish(); defer { monitor.stop() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
        for section in [PreferencesSection.general, .debug] {
            var requiredHeight: CGFloat = 0
            let host = NSHostingView(rootView: ContentView(monitor: monitor, section: section, onContentHeightChange: { requiredHeight = $0 }))
            host.frame = NSRect(x: 0, y: 0, width: 860, height: 800)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
            XCTAssertGreaterThan(requiredHeight, 300)
            XCTAssertLessThan(requiredHeight, 800)
            XCTAssertFalse(descendants(host).contains { $0 is NSScrollView })
            let before = requiredHeight
            host.frame.size.height = requiredHeight
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
            XCTAssertEqual(requiredHeight, before, accuracy: 1, "Height measurement must not depend on the available window height")
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(filePath: "/tmp/PenActor-fit-\(section.title).png"))
        }
        let controller = PreferencesWindowController(monitor: monitor)
        let window = try XCTUnwrap(controller.window)
        let tabs = try XCTUnwrap(window.contentViewController as? NSTabViewController)
        let initialWidth = window.contentRect(forFrameRect: window.frame).width
        for section in [PreferencesSection.general, .debug, .general] {
            tabs.selectedTabViewItemIndex = section.rawValue
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(window.contentRect(forFrameRect: window.frame).width, initialWidth, accuracy: 1)
            XCTAssertLessThan(window.contentRect(forFrameRect: window.frame).height, 650)
        }
        window.close()
    }

    @MainActor func testSettingsDockPresenceFollowsOpenAndCloseWithoutStoppingService() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = MappingPanelBackend(event: try XCTUnwrap(NSEvent(cgEvent: proximity())))
        let monitor = PenMonitor(backend: backend, profileRepository: .init(url: root.appending(path: "profiles.json")))
        monitor.start(); defer { monitor.stop() }
        var policies: [NSApplication.ActivationPolicy] = []
        let controller = PreferencesWindowController(monitor: monitor, setActivationPolicy: { policies.append($0) })
        XCTAssertTrue(policies.isEmpty, "Constructing the background controller must not show a Dock icon")
        let window = try XCTUnwrap(controller.window)
        controller.open(.debug)
        XCTAssertEqual(policies.last, .regular)
        XCTAssertTrue(window.isVisible)
        // Switching away / minimizing notifications must not request accessory mode.
        window.resignKey()
        NotificationCenter.default.post(name: NSWindow.didMiniaturizeNotification, object: window)
        XCTAssertFalse(policies.contains(.accessory))
        controller.open(.general)
        XCTAssertTrue(controller.window === window)
        XCTAssertEqual(policies.last, .regular)
        window.close()
        XCTAssertEqual(policies.last, .accessory)
        XCTAssertTrue(monitor.isRunning)
        controller.open()
        XCTAssertEqual(policies.last, .regular)
        XCTAssertTrue(window.isVisible)
        window.close()
        XCTAssertEqual(policies.last, .accessory)
    }

    @MainActor func testCompactNavigationSelectsAllPagesWithoutChangingWidth() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let monitor = PenMonitor(profileRepository: .init(url: root.appending(path: "profiles.json")))
        let controller = PreferencesWindowController(monitor: monitor, setActivationPolicy: { _ in })
        let window = try XCTUnwrap(controller.window)
        let tabs = try XCTUnwrap(window.contentViewController as? NSTabViewController)
        let control = try XCTUnwrap(window.toolbar?.items.compactMap { $0.view as? NSSegmentedControl }.first)
        XCTAssertEqual(window.toolbarStyle, .unifiedCompact)
        XCTAssertEqual(control.segmentCount, 4)
        XCTAssertLessThan(control.fittingSize.height, 34)
        let width = window.frame.width
        for section in PreferencesSection.allCases {
            XCTAssertEqual(control.label(forSegment: section.rawValue), section.title)
            control.selectedSegment = section.rawValue
            XCTAssertTrue(control.sendAction(control.action, to: control.target))
            XCTAssertEqual(tabs.selectedTabViewItemIndex, section.rawValue)
            XCTAssertEqual(window.frame.width, width, accuracy: 1)
        }
        tabs.selectedTabViewItemIndex = PreferencesSection.profiles.rawValue
        XCTAssertEqual(control.selectedSegment, PreferencesSection.profiles.rawValue)
        XCTAssertLessThan(window.frame.height - window.contentLayoutRect.height, 70)
        window.close()
    }

    @MainActor func testRapidVisiblePageSwitchesDoNotBlockAndKeepFinalGeometry() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let monitor = PenMonitor(profileRepository: .init(url: root.appending(path: "profiles.json")))
        let controller = PreferencesWindowController(monitor: monitor, setActivationPolicy: { _ in })
        let window = try XCTUnwrap(controller.window)
        let tabs = try XCTUnwrap(window.contentViewController as? NSTabViewController)
        window.setContentSize(NSSize(width: 900, height: 640))
        window.orderFront(nil)
        defer { window.close() }
        let width = window.frame.width, top = window.frame.maxY
        let start = ProcessInfo.processInfo.systemUptime
        for section in [PreferencesSection.testing, .general, .debug, .testing] {
            tabs.selectedTabViewItemIndex = section.rawValue
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        print("Rapid-page selection callback duration: \(elapsed) seconds")
        XCTAssertLessThan(elapsed, 0.18, "Selection callbacks must not run synchronous 0.2-second window animations")
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(tabs.selectedTabViewItemIndex, PreferencesSection.testing.rawValue)
        XCTAssertEqual(window.frame.width, width, accuracy: 1)
        XCTAssertEqual(window.frame.maxY, top, accuracy: 1)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).height, PreferencesSection.testing.defaultSize.height, accuracy: 1)
        tabs.selectedTabViewItemIndex = PreferencesSection.profiles.rawValue
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).height, 640, accuracy: 1)
        // Retarget while an earlier resize is still in flight.
        tabs.selectedTabViewItemIndex = PreferencesSection.testing.rawValue
        try await Task.sleep(for: .milliseconds(60))
        tabs.selectedTabViewItemIndex = PreferencesSection.profiles.rawValue
        try await Task.sleep(for: .milliseconds(60))
        tabs.selectedTabViewItemIndex = PreferencesSection.testing.rawValue
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).height, PreferencesSection.testing.defaultSize.height, accuracy: 1)
        XCTAssertEqual(window.contentMinSize.height, PreferencesSection.testing.minimumSize.height, accuracy: 1)
        XCTAssertEqual(window.frame.width, width, accuracy: 1)
        XCTAssertEqual(window.frame.maxY, top, accuracy: 1)
    }

    @MainActor func testPressureMeterDrawsLatestValueWithoutInheritedAnimation() throws {
        func meter(_ pressure: Double?) -> some View {
            PressureLevelBar(pressure: pressure).accentColor(.blue).frame(width: 200, height: 8)
                .animation(.linear(duration: 1), value: pressure)
        }
        let host = NSHostingView(rootView: meter(0.9))
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 8)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        func render(_ pressure: Double?) throws -> NSBitmapImageRep {
            host.rootView = meter(pressure)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            return bitmap
        }
        func filled(_ bitmap: NSBitmapImageRep, at fraction: Double) throws -> Bool {
            let color = try XCTUnwrap(bitmap.colorAt(x: Int(Double(bitmap.pixelsWide) * fraction), y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
            return color.blueComponent - color.redComponent > 0.2
        }
        XCTAssertTrue(try filled(render(0.9), at: 0.8))
        let dropped = try render(0.1)
        XCTAssertTrue(try filled(dropped, at: 0.05))
        XCTAssertFalse(try filled(dropped, at: 0.5), "A falling pressure must not retain an animated tail")
        for missing in [Double?.none, .some(0), .some(-1), .some(.nan)] {
            XCTAssertFalse(try filled(render(missing), at: 0.05))
        }
        XCTAssertTrue(try filled(render(2), at: 0.9))
        window.close()
    }

    @MainActor func testDeviceProfileAndOverrideEditorRenderWithSeparateNames() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let monitor = PenMonitor(profileRepository: .init(url: root.appending(path: "profiles.json")))
        let p = deviceProfile()
        XCTAssertTrue(monitor.saveProfile(p))
        var settings = monitor.mappingDefaults.settings(for: identity); settings.name = "我的 Pencil"; settings.configuration.curve = .light
        XCTAssertTrue(monitor.saveDeviceSettings(settings))
        let host = NSHostingView(rootView: DeviceProfilesPreferencesView(monitor: monitor, initialProfile: p).background(Color.white).environment(\.colorScheme, .light).frame(width: 860, height: 600))
        host.frame = NSRect(x: 0, y: 0, width: 860, height: 600)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(filePath: "/tmp/PenActor-device-profile.png"))
        var rule = try XCTUnwrap(p.applicationRules?.first); rule.mode = .custom
        rule.configuration.taper.entryEnabled = true; rule.configuration.taper.exitEnabled = true
        let editor = NSHostingView(rootView: ApplicationRuleEditor(rule: .constant(rule), base: settings.configuration).padding(16).background(Color.white).environment(\.colorScheme, .light).frame(width: 600))
        editor.frame = NSRect(x: 0, y: 0, width: 600, height: 480)
        editor.layoutSubtreeIfNeeded()
        let image = try XCTUnwrap(editor.bitmapImageRepForCachingDisplay(in: editor.bounds))
        editor.cacheDisplay(in: editor.bounds, to: image)
        try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: URL(filePath: "/tmp/PenActor-app-override.png"))
    }

    @MainActor func testMappingPanelRendersEditableProfile() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = PressureProfileRepository(url: root.appending(path: "profiles.json"))
        let backend = MappingPanelBackend(event: try XCTUnwrap(NSEvent(cgEvent: proximity())))
        let monitor = PenMonitor(backend: backend, profileRepository: repo)
        monitor.start(); monitor.publish()
        defer { monitor.stop() }
        var p = profile(); p.taper.entryEnabled = true; p.taper.exitEnabled = true
        XCTAssertTrue(monitor.saveProfile(p))
        let host = NSHostingView(rootView: DeviceProfilesPreferencesView(monitor: monitor, initialProfile: p).padding().frame(width: 1000, height: 860))
        host.frame = NSRect(x: 0, y: 0, width: 1000, height: 860)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(filePath: "/tmp/PenActor-mapping-panel.png"))
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        let full = NSHostingView(rootView: ContentView(monitor: monitor).frame(width: 1120, height: 1000))
        full.frame = NSRect(x: 0, y: 0, width: 1120, height: 1000)
        full.layoutSubtreeIfNeeded()
        let fullBitmap = try XCTUnwrap(full.bitmapImageRepForCachingDisplay(in: full.bounds))
        full.cacheDisplay(in: full.bounds, to: fullBitmap)
        try XCTUnwrap(fullBitmap.representation(using: .png, properties: [:])).write(to: URL(filePath: "/tmp/PenActor-window.png"))
    }
}
