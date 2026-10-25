import XCTest
import AppKit
import SwiftUI
@testable import PenActor

final class PressureMappingTests: XCTestCase {
    private let identity = PenIdentity(key: "v1:model:5ac:129a:0:pen", level: .model)
    private func profile(curve: PressureCurve = .light) -> PressureProfile {
        PressureProfile(name: "Pencil", device: identity, curve: curve, targetBundleIDs: ["com.adobe.Photoshop"])
    }
    private func proximity(id: Int64 = 17, entering: Bool = true, vendor: Int64 = 1452, type: CGEventType = .tabletProximity) throws -> CGEvent {
        let e = try XCTUnwrap(CGEvent(source: nil)); e.type = type
        if type != .tabletProximity { e.setIntegerValueField(.mouseEventSubtype, value: 2) }
        for (field, value): (CGEventField, Int64) in [(.tabletProximityEventDeviceID, id), (.tabletProximityEventVendorID, vendor),
            (.tabletProximityEventTabletID, 4762), (.tabletProximityEventPointerType, 1), (.tabletProximityEventEnterProximity, entering ? 1 : 0)] {
            e.setIntegerValueField(field, value: value)
        }
        return e
    }
    private func point(_ p: Double, id: Int64 = 17, pid: Int64 = 42, type: CGEventType = .tabletPointer, pen: Bool = true) throws -> CGEvent {
        let e = try XCTUnwrap(CGEvent(source: nil)); e.type = type; e.timestamp = 123_456_789
        e.setIntegerValueField(.eventTargetUnixProcessID, value: pid)
        if type != .tabletPointer { e.setIntegerValueField(.mouseEventSubtype, value: pen ? 1 : 0) }
        e.setIntegerValueField(.tabletEventDeviceID, value: id)
        e.setDoubleValueField(.tabletEventPointPressure, value: p); e.setDoubleValueField(.mouseEventPressure, value: p)
        e.setDoubleValueField(.tabletEventTiltX, value: 0.25)
        e.setDoubleValueField(.tabletEventRotation, value: 32)
        e.setIntegerValueField(.tabletEventPointButtons, value: 1)
        e.location = CGPoint(x: 120, y: 200)
        return e
    }
    private func processor(_ p: PressureProfile? = nil) -> PressureMappingProcessor {
        var m = PressureMappingProcessor(coordinateWritesEnabled: true); m.setProfiles([p ?? profile()]); m.applications = [42: "com.adobe.Photoshop", 43: "other.app"]
        return m
    }

    func testDefaultsResolutionAndApplicationPassthroughPriority() throws {
        var defaults = MappingDefaults()
        defaults.global.curve = .light
        var p = profile(curve: .linear)
        XCTAssertEqual(defaults.resolve(p, bundleID: "com.adobe.Photoshop")?.curve, .linear)
        p.usesDefaults = true
        XCTAssertEqual(defaults.resolve(p, bundleID: "com.adobe.Photoshop")?.curve, .light)
        var rule = ApplicationPressureRule(bundleID: "com.adobe.Photoshop", name: "Photoshop")
        rule.mode = .custom
        rule.configuration.taper.entryEnabled = true
        defaults.applications = [rule]
        XCTAssertEqual(defaults.resolve(p, bundleID: rule.bundleID)?.curve, .linear)
        XCTAssertTrue(try XCTUnwrap(defaults.resolve(p, bundleID: rule.bundleID)).taper.entryEnabled)
        XCTAssertEqual(defaults.resolve(p, bundleID: "other.app")?.curve, .light)
        p.usesDefaults = false
        XCTAssertFalse(try XCTUnwrap(defaults.resolve(p, bundleID: rule.bundleID)).taper.entryEnabled)
        defaults.applications[0].mode = .passthrough
        XCTAssertNil(defaults.resolve(p, bundleID: rule.bundleID))
    }

    func testDefaultsAreLatchedAndNeverOptInUnknownHardwareOrTargets() throws {
        var p = profile(curve: .linear); p.usesDefaults = true
        var m = processor(p); m.defaults.global.curve = .light
        m.process(try proximity())
        let first = try point(0.5); m.process(first)
        XCTAssertEqual(first.getDoubleValueField(.tabletEventPointPressure), 0.8, accuracy: 0.005)
        m.defaults.global.curve = .linear
        let held = try point(0.5); m.process(held)
        XCTAssertEqual(held.getDoubleValueField(.tabletEventPointPressure), 0.8, accuracy: 0.005)
        m.process(try point(0))
        let next = try point(0.5); m.process(next)
        XCTAssertEqual(next.getDoubleValueField(.tabletEventPointPressure), 0.5, accuracy: 0.005)
        m.process(try point(0)); m.defaults.global.curve = .light
        let other = try point(0.5, pid: 43); m.process(other)
        XCTAssertEqual(other.getDoubleValueField(.tabletEventPointPressure), 0.5, accuracy: 0.005)
        m.process(try proximity(id: 18, vendor: 1386))
        let wacom = try point(0.5, id: 18); m.process(wacom)
        XCTAssertEqual(wacom.getDoubleValueField(.tabletEventPointPressure), 0.5, accuracy: 0.005)
    }

    func testApplicationPassthroughChangeWaitsForNextStroke() throws {
        var m = processor(); m.process(try proximity()); m.process(try point(0.5))
        var rule = ApplicationPressureRule(bundleID: "com.adobe.Photoshop", name: "Photoshop")
        rule.mode = .passthrough; m.defaults.applications = [rule]
        let held = try point(0.5); m.process(held)
        XCTAssertEqual(held.getDoubleValueField(.tabletEventPointPressure), 0.8, accuracy: 0.005)
        m.process(try point(0)); let next = try point(0.5); m.process(next)
        XCTAssertEqual(next.getDoubleValueField(.tabletEventPointPressure), 0.5, accuracy: 0.005)
        XCTAssertNil(m.snapshot.diagnostics.last?.profileID)
    }

    func testDefaultsRepositoryRoundtripAndInvalidDataDoNotOverwrite() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = MappingDefaultsRepository(url: root.appending(path: "defaults.json"))
        XCTAssertEqual(try repo.load(), MappingDefaults())
        var defaults = MappingDefaults(); defaults.global.curve = .light
        defaults.applications = [.init(bundleID: "com.adobe.Photoshop", name: "Photoshop")]
        try repo.save(defaults)
        XCTAssertEqual(try repo.load(), defaults)
        var invalid = defaults; invalid.applications.append(invalid.applications[0])
        XCTAssertThrowsError(try repo.save(invalid))
        XCTAssertEqual(try repo.load(), defaults)
        invalid = defaults; invalid.schemaVersion = 99
        try JSONEncoder().encode(invalid).write(to: repo.url)
        XCTAssertThrowsError(try repo.load())
    }

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
        XCTAssertEqual(tabs.tabViewItems.map(\.label), ["通用", "配置", "调试", "测试"])
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

    private func touchRightEvent(_ type: CGEventType = .rightMouseDown, subtype: Int64? = nil, pid: Int64 = 42, source: Int64 = 9, number: Int64 = 15) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(source: nil))
        event.type = type; event.location = CGPoint(x: 125, y: 87); event.timestamp = 123456789
        event.setIntegerValueField(.mouseEventSubtype, value: subtype ?? Int64(NSEvent.EventSubtype.touch.rawValue))
        event.setIntegerValueField(.eventTargetUnixProcessID, value: pid)
        event.setIntegerValueField(.eventSourceUnixProcessID, value: source)
        event.setIntegerValueField(.mouseEventNumber, value: number)
        return event
    }
    private func touchFilter() -> TouchRightClickFilter {
        var filter = TouchRightClickFilter()
        filter.configure(enabled: true, targets: ["com.adobe.Photoshop"], applications: [42: "com.adobe.Photoshop", 43: "other.app"])
        return filter
    }
    func testTouchRightClickOnlyMatchesTaggedTargetAndNeverChangesEvent() throws {
        var filter = touchFilter()
        for subtype: Int64 in [0, 1, 2] { XCTAssertFalse(filter.suppress(try touchRightEvent(subtype: subtype))) }
        XCTAssertFalse(filter.suppress(try touchRightEvent(pid: 43)))
        XCTAssertFalse(filter.suppress(try touchRightEvent(pid: 0)))
        let control = try touchRightEvent(); control.flags = .maskControl
        XCTAssertFalse(filter.suppress(control))
        let event = try touchRightEvent()
        let original = event.data
        XCTAssertTrue(filter.suppress(event))
        XCTAssertEqual(event.data as Data?, original as Data?)
        XCTAssertEqual(filter.snapshot.suppressedPressCount, 1)
    }
    func testTouchRightClickSequenceSurvivesDisableAndTargetSwitch() throws {
        var filter = touchFilter()
        XCTAssertTrue(filter.suppress(try touchRightEvent()))
        filter.configure(enabled: false, targets: [], applications: [:])
        XCTAssertTrue(filter.suppress(try touchRightEvent(.rightMouseDragged, subtype: 0, pid: 43)))
        XCTAssertFalse(filter.suppress(try touchRightEvent(.rightMouseUp, source: 10)))
        XCTAssertFalse(filter.suppress(try touchRightEvent(.rightMouseUp, number: 16)))
        XCTAssertFalse(filter.suppress(try touchRightEvent(.rightMouseUp, subtype: 1)))
        XCTAssertTrue(filter.suppress(try touchRightEvent(.rightMouseUp, subtype: 0, pid: 43)))
        XCTAssertFalse(filter.suppress(try touchRightEvent(.rightMouseUp)))
        XCTAssertFalse(filter.suppress(try touchRightEvent()))
        XCTAssertEqual(filter.snapshot.suppressedEventCount, 3)
    }
    func testTouchRightClickDoesNotSwallowReleaseOfDeliveredDown() throws {
        var filter = TouchRightClickFilter()
        XCTAssertFalse(filter.suppress(try touchRightEvent()))
        filter.configure(enabled: true, targets: ["com.adobe.Photoshop"], applications: [42: "com.adobe.Photoshop"])
        XCTAssertFalse(filter.suppress(try touchRightEvent(.rightMouseUp)))
        XCTAssertTrue(filter.suppress(try touchRightEvent()))
        // Reusing an event number for an ordinary right click must not inherit suppression.
        XCTAssertFalse(filter.suppress(try touchRightEvent(subtype: 0)))
        XCTAssertFalse(filter.suppress(try touchRightEvent(.rightMouseUp, subtype: 0)))
        XCTAssertTrue(filter.suppress(try touchRightEvent(number: 0)))
        XCTAssertFalse(filter.suppress(try touchRightEvent(.rightMouseUp, subtype: 0, number: 0)))
        XCTAssertTrue(filter.suppress(try touchRightEvent(.rightMouseUp, number: 0)))
    }
    func testTouchRightClickLeavesNonRightEventsAloneAndBoundsDiagnostics() throws {
        var filter = touchFilter()
        for type: CGEventType in [.leftMouseDown, .leftMouseUp, .tabletPointer, .tabletProximity, .scrollWheel, .flagsChanged, .keyDown] {
            XCTAssertFalse(filter.suppress(try touchRightEvent(type)))
        }
        XCTAssertEqual(filter.snapshot.observedCount, 0)
        for i in 0..<600 { _ = filter.suppress(try touchRightEvent(subtype: 0, number: Int64(i))) }
        XCTAssertEqual(filter.snapshot.observedCount, 600)
        XCTAssertEqual(filter.snapshot.diagnostics.count, 500)
        filter.clear(); XCTAssertEqual(filter.snapshot.observedCount, 0)
        XCTAssertTrue(filter.snapshot.diagnostics.isEmpty)
    }
    func testTouchRightClickTapFailureAndSystemDisableStopWithoutRetry() {
        let failed = TouchRightClickEngine(createTap: { _, _, _ in nil })
        failed.configure(enabled: true, targets: ["com.adobe.Photoshop"], applications: [:])
        failed.start(); failed.start()
        for _ in 0..<100 where failed.snapshot().isStarting { Thread.sleep(forTimeInterval: 0.001) }
        XCTAssertFalse(failed.snapshot().enabled); XCTAssertFalse(failed.snapshot().isRunning)
        XCTAssertTrue(failed.snapshot().status.contains("无法创建"))
        failed.stop(); failed.stop()
        for type: CGEventType in [.tapDisabledByTimeout, .tapDisabledByUserInput] {
            let engine = TouchRightClickEngine(createTap: { _, callback, context in
                _ = callback(OpaquePointer(bitPattern: 1)!, type, CGEvent(source: nil)!, context)
                return nil
            })
            engine.configure(enabled: true, targets: ["com.adobe.Photoshop"], applications: [:]); engine.start()
            for _ in 0..<100 where engine.snapshot().isStarting { Thread.sleep(forTimeInterval: 0.001) }
            XCTAssertFalse(engine.snapshot().enabled); XCTAssertTrue(engine.snapshot().status.contains("系统停用了"))
        }
    }
    @MainActor func testTouchRightClickTargetsPersistButActivationDoesNotAndExportIncludesDiagnostics() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "PenActorTests." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let repository = PressureProfileRepository(url: root.appending(path: "profiles.json"))
        let monitor = PenMonitor(preferences: preferences, profileRepository: repository)
        XCTAssertFalse(monitor.touchBlocking.enabled)
        monitor.addTouchBlockingTarget("test.app"); monitor.addTouchBlockingTarget("test.app")
        XCTAssertEqual(monitor.touchBlockingTargets.filter { $0 == "test.app" }.count, 1)
        let restored = PenMonitor(preferences: preferences, profileRepository: repository)
        XCTAssertTrue(restored.touchBlockingTargets.contains("test.app")); XCTAssertFalse(restored.touchBlocking.enabled)
        monitor.setTouchBlocking(true)
        XCTAssertFalse(monitor.touchBlocking.enabled); XCTAssertNotNil(monitor.touchBlockingError)
        var filter = touchFilter(); _ = filter.suppress(try touchRightEvent())
        let document = PenLogDocument(store: PenStore(), interactions: PencilInteractionStats(), isMonitoring: true, touchBlocking: filter.snapshot)
        let decoded = try JSONDecoder().decode(TouchRightClickSnapshot.self, from: JSONEncoder().encode(filter.snapshot))
        XCTAssertEqual(decoded, filter.snapshot)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: document.jsonData()) as? [String: Any])
        let exported = try XCTUnwrap(object["touchBlocking"] as? [String: Any])
        XCTAssertEqual(exported["suppressedPressCount"] as? Int, 1)
        monitor.removeTouchBlockingTarget("test.app")
        XCTAssertFalse(monitor.touchBlockingTargets.contains("test.app"))
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

    @MainActor func testPrivacySettingsNavigationUsesCorrectPagesAndFallback() {
        for pane in [PrivacySettingsPane.inputMonitoring, .accessibility] {
            var opened: [URL] = []
            let navigator = PrivacySettingsNavigator(openURL: { opened.append($0); return true })
            XCTAssertTrue(navigator.open(pane))
            XCTAssertEqual(opened.count, 1)
            XCTAssertEqual(opened.first?.query, pane == .inputMonitoring ? "Privacy_ListenEvent" : "Privacy_Accessibility")
            XCTAssertEqual(opened.first?.scheme, "x-apple.systempreferences")
        }
        var opened: [URL] = []
        let fallback = PrivacySettingsNavigator(openURL: { opened.append($0); return opened.count == 2 })
        XCTAssertTrue(fallback.open(.inputMonitoring))
        XCTAssertEqual(opened.count, 2)
        XCTAssertNil(opened.last?.query)
        let unavailable = PrivacySettingsNavigator(openURL: { _ in false })
        XCTAssertFalse(unavailable.open(.accessibility))
    }

    func testLegacyBundlePreferencesMigrateOnceWithoutOverwritingNewSettings() throws {
        let suite = "PenActorTests." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(true, forKey: "showSettingsOnLaunch")
        let legacy: [String: Any] = ["showSettingsOnLaunch": false, "automaticallySwitchDevices": false,
            "touchBlockingTargets": ["test.app"], "unrelatedKey": "ignore"]
        LegacyPreferencesMigration.migrate(legacy: legacy, into: preferences)
        XCTAssertTrue(preferences.bool(forKey: "showSettingsOnLaunch"))
        XCTAssertEqual(preferences.object(forKey: "automaticallySwitchDevices") as? Bool, false)
        XCTAssertEqual(preferences.stringArray(forKey: "touchBlockingTargets"), ["test.app"])
        XCTAssertNil(preferences.object(forKey: "unrelatedKey"))
        preferences.removeObject(forKey: "automaticallySwitchDevices")
        LegacyPreferencesMigration.migrate(legacy: legacy, into: preferences)
        XCTAssertNil(preferences.object(forKey: "automaticallySwitchDevices"))
    }

    func testEditorDraftIgnoresNoOpCallbacksAndRestoredValues() {
        var state = DeviceProfileDraftState()
        let settings = DevicePressureDefaults(device: identity, name: "Pencil")
        let p = deviceProfile()
        state.load(device: settings, profile: p)
        state.setDeviceName("Pencil", for: identity)
        state.setProfileName(p.name, for: p.id)
        XCTAssertFalse(state.hasChanges)
        state.setDeviceName("Changed", for: identity); XCTAssertTrue(state.hasChanges)
        state.setDeviceName("Pencil", for: identity); XCTAssertFalse(state.hasChanges)
        state.profile?.applicationRules?[0].mode = .custom; XCTAssertTrue(state.hasChanges)
        state.profile = p; XCTAssertFalse(state.hasChanges)
        state.device?.configuration.curve = .light; XCTAssertTrue(state.hasChanges)
    }
    func testEditorDraftRejectsLateCallbacksAfterSwitchingDevicesAndProfiles() {
        var state = DeviceProfileDraftState()
        let oldProfile = deviceProfile()
        let other = PenIdentity(key: "v1:tool:56a:123:pen", level: .uniqueTool)
        let currentProfile = deviceProfile(other)
        let settings = DevicePressureDefaults(device: other, name: "Wacom")
        state.load(device: settings, profile: currentProfile)
        state.setDeviceName("Old pencil field editor", for: identity)
        state.setProfileName("Old profile field editor", for: oldProfile.id)
        XCTAssertEqual(state.device, settings)
        XCTAssertEqual(state.profile, currentProfile)
        XCTAssertFalse(state.hasChanges)
    }
    func testSavingDeviceNameDoesNotClearUnsavedCurveOrProfileChanges() throws {
        var state = DeviceProfileDraftState()
        let settings = DevicePressureDefaults(device: identity, name: "Pencil")
        let p = deviceProfile()
        state.load(device: settings, profile: p)
        state.device?.configuration.curve = .light
        state.setDeviceName("My Pencil", for: identity)
        state.profile?.name = "Edited profile"
        var savedName = settings; savedName.name = "My Pencil"
        state.didSaveDevice(savedName)
        XCTAssertTrue(state.hasChanges)
        state.didSaveDevice(try XCTUnwrap(state.device))
        XCTAssertTrue(state.hasChanges, "Saving the device must not discard unsaved profile changes")
        state.didSaveProfile(try XCTUnwrap(state.profile))
        XCTAssertFalse(state.hasChanges)
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

    private func deviceProfile(_ device: PenIdentity? = nil) -> PressureProfile {
        PressureProfile(name: "绘画", device: device ?? identity, applicationRules: [
            ApplicationPressureRule(bundleID: "com.adobe.Photoshop", name: "Photoshop"),
            ApplicationPressureRule(bundleID: "other.app", name: "CSP fixture")
        ])
    }

    func testDeviceDefaultsAreIndependentAndOverridesStayWithinProfile() throws {
        let wacom = PenIdentity(key: "v1:model:56a:129a:0:pen", level: .model)
        var defaults = MappingDefaults()
        defaults.global.curve = .light // Retired global fields cannot affect new-style profiles.
        var retiredRule = ApplicationPressureRule(bundleID: "com.adobe.Photoshop", name: "retired")
        retiredRule.mode = .passthrough; defaults.applications = [retiredRule]
        defaults.devices = [.init(device: identity, name: "我的 Pencil", configuration: .init(curve: .light)), .init(device: wacom, name: "我的 Wacom")]
        var pencil = deviceProfile()
        let tablet = deviceProfile(wacom)
        XCTAssertEqual(defaults.resolve(pencil, bundleID: "com.adobe.Photoshop")?.curve, .light)
        XCTAssertEqual(defaults.resolve(tablet, bundleID: "com.adobe.Photoshop")?.curve, .linear)
        pencil.applicationRules?[0].mode = .custom
        pencil.applicationRules?[0].configuration.taper.entryEnabled = true
        XCTAssertEqual(defaults.resolve(pencil, bundleID: "com.adobe.Photoshop")?.curve, .linear)
        XCTAssertTrue(try XCTUnwrap(defaults.resolve(pencil, bundleID: "com.adobe.Photoshop")).taper.entryEnabled)
        XCTAssertEqual(defaults.resolve(pencil, bundleID: "other.app")?.curve, .light)
        XCTAssertFalse(try XCTUnwrap(defaults.resolve(tablet, bundleID: "com.adobe.Photoshop")).taper.entryEnabled)
        pencil.applicationRules?[0].mode = .passthrough
        XCTAssertNil(defaults.resolve(pencil, bundleID: "com.adobe.Photoshop"))
        XCTAssertNotNil(defaults.resolve(tablet, bundleID: "com.adobe.Photoshop"))
        XCTAssertNil(defaults.resolve(pencil, bundleID: "unlisted.app"))
    }

    func testDeviceDefaultChangesLatchUntilNextStrokeAndDoNotChangeOverrides() throws {
        var p = deviceProfile()
        p.applicationRules?[1].mode = .custom
        p.applicationRules?[1].configuration.curve = .light
        var m = processor(p)
        m.defaults.devices = [.init(device: identity, configuration: .init(curve: .light))]
        m.process(try proximity())
        let first = try point(0.5); m.process(first)
        XCTAssertEqual(first.getDoubleValueField(.tabletEventPointPressure), 0.8, accuracy: 0.005)
        m.defaults.devices[0].configuration.curve = .linear
        let held = try point(0.5); m.process(held)
        XCTAssertEqual(held.getDoubleValueField(.tabletEventPointPressure), 0.8, accuracy: 0.005)
        m.process(try point(0))
        let next = try point(0.5); m.process(next)
        XCTAssertEqual(next.getDoubleValueField(.tabletEventPointPressure), 0.5, accuracy: 0.005)
        m.process(try point(0))
        let override = try point(0.5, pid: 43); m.process(override)
        XCTAssertEqual(override.getDoubleValueField(.tabletEventPointPressure), 0.8, accuracy: 0.005)
    }

    func testQuartzSeparatesDevicesWithSameTargetAndKeepsUnconfiguredDevicesUntouched() throws {
        let wacom = PenIdentity(key: "v1:model:56a:129a:0:pen", level: .model)
        var m = processor(deviceProfile())
        m.setProfiles([deviceProfile(), deviceProfile(wacom)])
        m.defaults.devices = [.init(device: identity, configuration: .init(curve: .light)), .init(device: wacom)]
        m.process(try proximity()); m.process(try proximity(id: 18, vendor: 1386))
        let pencil = try point(0.5), tablet = try point(0.5, id: 18)
        m.process(pencil); m.process(tablet)
        XCTAssertEqual(pencil.getDoubleValueField(.tabletEventPointPressure), 0.8, accuracy: 0.005)
        XCTAssertEqual(tablet.getDoubleValueField(.tabletEventPointPressure), 0.5, accuracy: 0.005)
        m.process(try proximity(id: 19, vendor: 99))
        let unknown = try point(0.5, id: 19); m.process(unknown)
        XCTAssertEqual(unknown.getDoubleValueField(.tabletEventPointPressure), 0.5, accuracy: 0.005)
    }

    func testMigrationPreservesPerApplicationBehaviorAndIsRepeatable() throws {
        var defaults = MappingDefaults(); defaults.schemaVersion = 1; defaults.global.curve = .linear
        var ps = ApplicationPressureRule(bundleID: "com.adobe.Photoshop", name: "Photoshop")
        ps.mode = .custom; ps.configuration.curve = .light; ps.configuration.taper.entryEnabled = true
        var blocked = ApplicationPressureRule(bundleID: "other.app", name: "excluded"); blocked.mode = .passthrough
        defaults.applications = [ps, blocked]
        var a = profile(); a.targetBundleIDs.append("other.app")
        var b = profile(curve: .linear); b.targetBundleIDs.append("other.app")
        var c = profile(); c.device = PenIdentity(key: "another-device", level: .uniqueTool)
        c.usesDefaults = true; c.targetBundleIDs.append("other.app")
        let old = [a, b, c]
        let migration = defaults.migrating(old)
        XCTAssertEqual(migration.defaults.devices.count, 2)
        XCTAssertEqual(migration.profiles.map(\.id), old.map(\.id))
        for (before, after) in zip(old, migration.profiles) {
            XCTAssertEqual(after.effectiveTargetBundleIDs, before.targetBundleIDs)
            for id in before.targetBundleIDs {
                let original = defaults.resolve(before, bundleID: id)
                let resolved = migration.defaults.resolve(after, bundleID: id)
                XCTAssertEqual(original?.curve, resolved?.curve)
                XCTAssertEqual(original?.taper, resolved?.taper)
            }
        }
        XCTAssertEqual(migration.profiles[1].applicationRules?.first?.mode, .custom)
        let again = migration.defaults.migrating(migration.profiles)
        XCTAssertEqual(again.defaults, migration.defaults); XCTAssertEqual(again.profiles, migration.profiles)
        // Simulate interruption after defaults.json saved, but before profiles.json replaced.
        XCTAssertEqual(migration.defaults.migrating(old).profiles, migration.profiles)
    }

    @MainActor func testMonitorMigrationBacksUpOriginalsAndDeviceRenamePersistsAfterProfileDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = PressureProfileRepository(url: root.appending(path: "profiles.json"))
        let defaultsRepo = MappingDefaultsRepository(url: root.appending(path: "defaults.json"))
        try repo.save([profile()]); try defaultsRepo.save(MappingDefaults())
        let original = try Data(contentsOf: repo.url)
        let monitor = PenMonitor(profileRepository: repo)
        XCTAssertNotNil(monitor.profiles.first?.applicationRules)
        let folders = try FileManager.default.contentsOfDirectory(at: root.appending(path: "Backups"), includingPropertiesForKeys: nil)
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(try Data(contentsOf: folders[0].appending(path: "profiles.json")), original)
        var settings = monitor.mappingDefaults.settings(for: identity); settings.name = "我的笔"
        XCTAssertTrue(monitor.saveDeviceSettings(settings))
        let id = try XCTUnwrap(monitor.profiles.first?.id)
        monitor.deleteProfile(id)
        let restored = PenMonitor(profileRepository: repo)
        XCTAssertTrue(restored.profiles.isEmpty)
        XCTAssertEqual(restored.deviceDisplayName(identity), "我的笔")
        XCTAssertEqual(restored.mappingDefaults.settings(for: identity).configuration.curve, .light)
        XCTAssertTrue(restored.enabledProfileIDs.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: root.appending(path: "Backups"), includingPropertiesForKeys: nil).count, 1)
    }

    func testDeviceScopedValidationRejectsDuplicateApplicationsAndDevices() {
        var p = deviceProfile()
        let duplicate = p.applicationRules![0]; p.applicationRules?.append(duplicate); XCTAssertFalse(p.isValid)
        p = deviceProfile(); p.applicationRules?[0].configuration.curve.points = []; XCTAssertFalse(p.isValid)
        var defaults = MappingDefaults()
        defaults.devices = [.init(device: identity), .init(device: identity)]; XCTAssertFalse(defaults.isValid)
        defaults.devices = [.init(device: .session(17))]; XCTAssertFalse(defaults.isValid)
    }

    @MainActor func testCorruptDefaultsBlockMigrationSavingAndDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = PressureProfileRepository(url: root.appending(path: "profiles.json"))
        try repo.save([profile()])
        let original = try Data(contentsOf: repo.url)
        let bad = root.appending(path: "defaults.json")
        try Data("invalid".utf8).write(to: bad)
        let monitor = PenMonitor(profileRepository: repo)
        XCTAssertNotNil(monitor.profileError)
        XCTAssertFalse(monitor.saveProfile(deviceProfile()))
        XCTAssertFalse(monitor.saveDefaults(MappingDefaults()))
        monitor.deleteProfile(try XCTUnwrap(monitor.profiles.first?.id))
        XCTAssertEqual(try Data(contentsOf: repo.url), original)
        XCTAssertEqual(try Data(contentsOf: bad), Data("invalid".utf8))
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

    func testCurvesAreMonotoneBoundedAndHitControlPoints() {
        for curve in [PressureCurve.linear, .light, PressureCurve(points: [.init(x: 0,y: 0), .init(x: 0.2,y: 0), .init(x: 0.7,y: 1), .init(x: 1,y: 1)])] {
            XCTAssertTrue(curve.isValid)
            var previous = 0.0
            for i in 0...1000 {
                let y = curve.map(Double(i)/1000)
                XCTAssertGreaterThanOrEqual(y, previous); XCTAssertLessThanOrEqual(y, 1); previous = y
            }
            for p in curve.points { XCTAssertEqual(curve.map(p.x), p.y, accuracy: 1e-12) }
        }
        XCTAssertEqual(PressureCurve.light.map(0.5), 0.8, accuracy: 1e-12)
        XCTAssertEqual(PressureCurve.linear.map(0.378), 0.378, accuracy: 1e-12)
        XCTAssertEqual(PressureCurve.light.map(-1), 0); XCTAssertEqual(PressureCurve.light.map(2), 1)
        XCTAssertEqual(PressureCurve.light.map(.nan), 0)
    }
    func testInvalidCurvesAndProfilesAreRejected() {
        for points: [PressurePoint] in [[], [.init(x: 0,y: 0)], [.init(x: 0,y: 0), .init(x: 0,y: 1)],
            [.init(x: 0,y: 0), .init(x: 0.5,y: 0.8), .init(x: 0.6,y: 0.7), .init(x: 1,y: 1)],
            [.init(x: 0,y: 0), .init(x: .nan,y: 0.5), .init(x: 1,y: 1)]] {
            let curve = PressureCurve(points: points); XCTAssertFalse(curve.isValid); XCTAssertEqual(curve.map(0.3), 0.3)
        }
        var p = profile(); p.device = .session(17); XCTAssertFalse(p.isValid)
        p = profile(); p.name = "  "; XCTAssertFalse(p.isValid)
    }
    func testPlateausAndZeroStayZero() {
        let curve = PressureCurve(points: [.init(x: 0,y: 0), .init(x: 0.2,y: 0), .init(x: 0.7,y: 1), .init(x: 1,y: 1)])
        XCTAssertEqual(curve.map(0.1), 0); XCTAssertEqual(curve.map(0.9), 1)
    }
    func testOnlyMatchingDeviceAndApplicationAreModified() throws {
        for (id,pid,expected): (Int64,Int64,Double) in [(17,42,0.8),(18,42,0.5),(17,43,0.5),(17,99,0.5)] {
            var m = processor(); m.process(try proximity()); let e = try point(0.5,id: id,pid: pid); m.process(e)
            XCTAssertEqual(e.getDoubleValueField(.tabletEventPointPressure), expected, accuracy: 0.005)
            XCTAssertEqual(m.snapshot.diagnostics.last?.outputPressure ?? -1, expected, accuracy: 0.005)
        }
        var m = processor(); m.process(try proximity(vendor: 1386)); let e = try point(0.5); m.process(e)
        XCTAssertEqual(e.getDoubleValueField(.tabletEventPointPressure), 0.5, accuracy: 0.005)
    }
    func testMouseAndStandaloneModificationPreserveOtherFields() throws {
        for type: CGEventType in [.tabletPointer, .leftMouseDown, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged] {
            var m = processor(); m.process(try proximity()); let e = try point(0.5,type: type)
            let before = try XCTUnwrap(NSEvent(cgEvent: e)); let timestamp = e.timestamp
            m.process(e)
            let after = try XCTUnwrap(NSEvent(cgEvent: e))
            XCTAssertEqual(after.pressure, 0.8, accuracy: 0.005)
            XCTAssertEqual(e.timestamp, timestamp); XCTAssertEqual(e.location, CGPoint(x:120,y:200))
            XCTAssertEqual(after.tilt.x,before.tilt.x); XCTAssertEqual(after.rotation,before.rotation)
            XCTAssertEqual(after.buttonMask,before.buttonMask); XCTAssertEqual(after.deviceID,before.deviceID)
            XCTAssertEqual(e.getIntegerValueField(.eventTargetUnixProcessID), 42)
        }
    }
    func testOrdinaryMouseAndHoverAreIgnored() throws {
        var m = processor(); m.process(try proximity())
        for type: CGEventType in [.leftMouseDown,.leftMouseDragged,.mouseMoved] {
            let e = try point(0.5,type: type,pen: false); m.process(e)
            XCTAssertEqual(e.getDoubleValueField(.mouseEventPressure),0.5,accuracy:0.005)
        }
        m.process(try point(0.5,type: .mouseMoved)); XCTAssertTrue(m.snapshot.diagnostics.isEmpty)
    }
    func testStrokeLatchesCurveUntilZeroPressure() throws {
        var m = processor(); m.process(try proximity()); m.process(try point(0.5))
        var updated = m.profiles[0]; updated.curve = .linear; m.setProfiles([updated])
        let e = try point(0.5,type: .leftMouseDown); m.process(e)
        XCTAssertEqual(e.getDoubleValueField(.mouseEventPressure),0.8,accuracy:0.005)
        m.process(try point(0)); let next = try point(0.5); m.process(next)
        XCTAssertEqual(next.getDoubleValueField(.tabletEventPointPressure),0.5,accuracy:0.005)
    }
    func testProfileSwitchWaitsUntilNextStrokeAndDisableIsImmediate() throws {
        var m = processor(); m.process(try proximity()); m.process(try point(0.5))
        let replacement = profile(curve:.linear); m.setProfiles([replacement])
        let held = try point(0.5); m.process(held)
        XCTAssertEqual(held.getDoubleValueField(.tabletEventPointPressure),0.8,accuracy:0.005)
        m.setProfiles([]); let disabled = try point(0.5); m.process(disabled)
        XCTAssertEqual(disabled.getDoubleValueField(.tabletEventPointPressure),0.5,accuracy:0.005)
    }
    func testEnablingMidstrokeWaitsAndPlainMouseUpReleasesLatch() throws {
        var m = processor(); m.setProfiles([]); m.process(try proximity()); m.process(try point(0.5))
        m.setProfiles([profile()]); let held = try point(0.5); m.process(held)
        XCTAssertEqual(held.getDoubleValueField(.tabletEventPointPressure),0.5,accuracy:0.005)
        m.process(try point(0,type:.leftMouseUp,pen:false)); let next = try point(0.5); m.process(next)
        XCTAssertEqual(next.getDoubleValueField(.tabletEventPointPressure),0.8,accuracy:0.005)
    }
    func testReconnectExitAndRecycledDeviceID() throws {
        var m = processor(); m.process(try proximity()); m.process(try point(0.5))
        m.process(try proximity(entering:false)); let exited = try point(0.5); m.process(exited)
        XCTAssertEqual(m.snapshot.diagnostics.last?.reason,"等待 proximity 识别设备")
        m.process(try proximity(id:18)); let reconnected = try point(0.5,id:18); m.process(reconnected)
        XCTAssertEqual(reconnected.getDoubleValueField(.tabletEventPointPressure),0.8,accuracy:0.005)
        m.process(try proximity(id:18,vendor:1386)); let reused = try point(0.5,id:18); m.process(reused)
        XCTAssertEqual(reused.getDoubleValueField(.tabletEventPointPressure),0.5,accuracy:0.005)
    }
    func testZeroAndDisableNeverIntroduceContactAndCacheIsBounded() throws {
        var m = processor(); m.process(try proximity()); m.process(try point(0.5)); let zero = try point(0); m.process(zero)
        XCTAssertEqual(zero.getDoubleValueField(.tabletEventPointPressure),0)
        for _ in 0..<600 { m.process(try point(0.5)) }
        XCTAssertEqual(m.snapshot.diagnostics.count,500)
        m.disable(); let e = try point(0.5); m.process(e)
        XCTAssertEqual(e.getDoubleValueField(.tabletEventPointPressure),0.5,accuracy:0.005)
        XCTAssertNil(m.snapshot.diagnostics.last?.device)
    }
    func testProfilePersistenceAndInvalidFileIsNotOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let repo = PressureProfileRepository(url:root.appending(path:"profiles.json"))
        XCTAssertTrue(try repo.load().isEmpty)
        try repo.save([profile()]); XCTAssertEqual(try repo.load().first?.curve,.light)
        let original = try Data(contentsOf:repo.url); var invalid = profile(); invalid.device = .session(1)
        XCTAssertThrowsError(try repo.save([invalid])); XCTAssertEqual(try Data(contentsOf:repo.url),original)
        try Data("{\"schemaVersion\":99,\"profiles\":[]}".utf8).write(to:repo.url)
        XCTAssertThrowsError(try repo.load())
    }
    func testExportContainsIndependentMappingSnapshot() throws {
        var m = processor(); m.process(try proximity()); m.process(try point(0.5))
        let document = PenLogDocument(store:PenStore(),interactions:PencilInteractionStats(),isMonitoring:true,profiles:[profile()],mapping:m.snapshot)
        let data = try document.jsonData()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertEqual(object["schemaVersion"] as? Int,3)
        XCTAssertEqual(document.events.count,0); XCTAssertEqual(document.mapping.diagnostics.count,1)
        XCTAssertEqual(document.mapping.diagnostics[0].inputPressure,0.5,accuracy:0.005)
        XCTAssertEqual(document.mapping.diagnostics[0].outputPressure,0.8,accuracy:0.005)
    }
    func testTapCreationFailureAndRepeatedStopRemainPassthrough() {
        let engine = PressureRemappingEngine(createTap: { _,_,_ in nil })
        engine.start(); engine.start()
        for _ in 0..<100 where engine.snapshot().isStarting { Thread.sleep(forTimeInterval:0.001) }
        XCTAssertFalse(engine.snapshot().isRunning)
        XCTAssertTrue(engine.snapshot().status.contains("无法创建"))
        engine.stop(); engine.stop(); XCTAssertFalse(engine.snapshot().isRunning)
        XCTAssertTrue(engine.snapshot().activeProfiles.isEmpty)
    }
    func testMouseProximitySubtypesEstablishAndEndAssociation() throws {
        for type: CGEventType in [.mouseMoved, .leftMouseDown, .leftMouseDragged] {
            var m = processor(); m.process(try proximity(type: type))
            let e = try point(0.5); m.process(e)
            XCTAssertEqual(e.getDoubleValueField(.tabletEventPointPressure), 0.8, accuracy: 0.005)
            m.process(try proximity(entering: false, type: type))
            m.process(try point(0.5)); XCTAssertNil(m.snapshot.diagnostics.last?.device)
        }
    }
    func testDisablingAndReenablingBeforeLiftOffKeepsStrokePassthrough() throws {
        var m = processor(); m.process(try proximity()); m.process(try point(0.5))
        let p = m.profiles[0]
        m.setProfiles([]); m.setProfiles([p])
        let held = try point(0.5); m.process(held)
        XCTAssertEqual(held.getDoubleValueField(.tabletEventPointPressure), 0.5, accuracy: 0.005)
        m.process(try point(0)); let next = try point(0.5); m.process(next)
        XCTAssertEqual(next.getDoubleValueField(.tabletEventPointPressure), 0.8, accuracy: 0.005)
    }
    func testUntargetedPreludeDoesNotBlockApplicationMouseDown() throws {
        var m = processor(); m.process(try proximity())
        m.process(try point(0.5, pid: 0))
        let e = try point(0.5, type: .leftMouseDown); m.process(e)
        XCTAssertEqual(e.getDoubleValueField(.mouseEventPressure), 0.8, accuracy: 0.005)
        let untargeted = try point(0.5, pid: 0); m.process(untargeted)
        XCTAssertEqual(untargeted.getDoubleValueField(.tabletEventPointPressure), 0.5, accuracy: 0.005)
    }
    func testQuartzAndAppKitResolveSameToolIdentity() throws {
        for tool: Int64 in [1,2,3] {
            let entry = try proximity(vendor: 1386)
            entry.setIntegerValueField(.tabletProximityEventPointerType, value: tool)
            entry.setIntegerValueField(.tabletProximityEventVendorUniqueID, value: 72568412843458)
            entry.setIntegerValueField(.tabletProximityEventVendorPointerSerialNumber, value: 645410242)
            let decoded = try XCTUnwrap(PenEventDecoder.decode(try XCTUnwrap(NSEvent(cgEvent: entry)), source: .global, foregroundApp: ""))
            let expected = PenIdentity.resolve(info: try XCTUnwrap(decoded.info), deviceID: 17)
            var m = processor(); m.process(entry); m.process(try point(0.5))
            XCTAssertEqual(m.snapshot.diagnostics.last?.device, expected)
        }
    }
    func testTimeoutAndUserDisableDoNotAutomaticallyRestart() {
        for type: CGEventType in [.tapDisabledByTimeout, .tapDisabledByUserInput] {
            let engine = PressureRemappingEngine(createTap: { _, callback, context in
                _ = callback(OpaquePointer(bitPattern: 1)!, type, CGEvent(source: nil)!, context)
                return nil
            })
            engine.start()
            for _ in 0..<100 where engine.snapshot().isStarting { Thread.sleep(forTimeInterval: 0.001) }
            XCTAssertFalse(engine.snapshot().isRunning)
            XCTAssertTrue(engine.snapshot().status.contains("系统停用了"))
            XCTAssertTrue(engine.snapshot().activeProfiles.isEmpty)
        }
    }
    func testLinearProfileDoesNotQuantizeOrRewritePressure() throws {
        for type: CGEventType in [.tabletPointer, .leftMouseDragged] {
            var m = processor(profile(curve: .linear)); m.process(try proximity())
            let e = try point(0.378, type: type)
            let a = e.getDoubleValueField(.mouseEventPressure), b = e.getDoubleValueField(.tabletEventPointPressure)
            m.process(e)
            XCTAssertEqual(e.getDoubleValueField(.mouseEventPressure), a)
            XCTAssertEqual(e.getDoubleValueField(.tabletEventPointPressure), b)
            XCTAssertEqual(m.snapshot.modifiedEventCount, 0)
        }
    }
    @MainActor func testMonitorPersistsProfilesButNeverRestoresActivation() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = PressureProfileRepository(url: root.appending(path: "profiles.json"))
        let monitor = PenMonitor(profileRepository: repo)
        XCTAssertTrue(monitor.saveProfile(profile()))
        monitor.clear()
        XCTAssertEqual(monitor.profiles.count, 1)
        let reloaded = PenMonitor(profileRepository: repo)
        XCTAssertEqual(reloaded.profiles.count, 1)
        XCTAssertTrue(reloaded.enabledProfileIDs.isEmpty)
        XCTAssertFalse(reloaded.mapping.isRunning)
        reloaded.stop(); reloaded.start(); reloaded.stop()
        XCTAssertTrue(reloaded.enabledProfileIDs.isEmpty)
    }

    func testLegacyProfilesPreserveCustomValuesAndSaveAsVersionFive() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repo = PressureProfileRepository(url: root.appending(path: "profiles.json"))
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile())) as? [String: Any])
        old.removeValue(forKey: "taper"); old.removeValue(forKey: "usesDefaults")
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "profiles": [old]]).write(to: repo.url)
        let loaded = try repo.load()
        XCTAssertEqual(loaded.first?.taper, StrokeTaperSettings())
        XCTAssertEqual(loaded.first?.usesDefaults, false)
        XCTAssertEqual(loaded.first?.curve, .light)
        try repo.save(loaded)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: repo.url)) as? [String: Any])
        XCTAssertEqual(saved["schemaVersion"] as? Int, 5)
    }
    func testInvalidTaperSettingsAreRejected() {
        var p = profile()
        p.taper.entryDistance = 0; XCTAssertFalse(p.isValid)
        p.taper = StrokeTaperSettings(); p.taper.entryDurationMS = .nan; XCTAssertFalse(p.isValid)
        p.taper = StrokeTaperSettings(); p.taper.exitDurationMS = 1; XCTAssertFalse(p.isValid)
        p.taper = StrokeTaperSettings(); p.taper.exitDurationMS = .infinity; XCTAssertFalse(p.isValid)
    }
    private func shape(_ state: inout StrokeTaperState, settings: StrokeTaperSettings, pressure: Double = 0.5,
                       time: Double, x: Double = 0, ending: Bool = false)
        -> (pressure: Double, tabletPressure: Double, diagnostic: StrokeTaperDiagnostic) {
        state.apply(settings: settings, input: pressure, tabletInput: pressure, curvePressure: pressure,
                    tabletCurvePressure: pressure, timestamp: time, location: CGPoint(x: x, y: 0), isEnding: ending)
    }
    func testEntryStartsAtZeroAndSmoothlyRestoresPressureByTime() {
        var settings = StrokeTaperSettings(); settings.entryEnabled = true
        var state = StrokeTaperState()
        XCTAssertEqual(shape(&state, settings: settings, pressure: 0.0784, time: 1).pressure, 0)
        XCTAssertEqual(shape(&state, settings: settings, pressure: 0.0784, time: 1).pressure, 0)
        let halfway = shape(&state, settings: settings, pressure: 0.0784, time: 1.03)
        XCTAssertEqual(halfway.pressure, 0.0392, accuracy: 1e-9)
        XCTAssertEqual(halfway.diagnostic.entryFactor, 0.5, accuracy: 1e-9)
        XCTAssertEqual(shape(&state, settings: settings, pressure: 0.0784, time: 1.06).pressure, 0.0784, accuracy: 1e-9)
    }
    func testEntryUsesCumulativeScreenDistanceAndDoesNotRegress() {
        var settings = StrokeTaperSettings(); settings.entryEnabled = true; settings.entryDurationMS = 500
        var state = StrokeTaperState()
        _ = shape(&state, settings: settings, time: 1)
        XCTAssertEqual(shape(&state, settings: settings, time: 1.001, x: 6).pressure, 0.25, accuracy: 1e-9)
        let backwards = shape(&state, settings: settings, time: 0.9, x: 100)
        XCTAssertEqual(backwards.diagnostic.distance, 6)
        XCTAssertEqual(backwards.pressure, 0.25, accuracy: 1e-9)
        let returned = shape(&state, settings: settings, time: 1.002, x: 0)
        XCTAssertEqual(returned.diagnostic.distance, 12)
        XCTAssertEqual(returned.pressure, 0.5)
    }
    func testEntryTimeLimitRecoversStationaryDotsOnLaterSamples() {
        var settings = StrokeTaperSettings(); settings.entryEnabled = true
        var state = StrokeTaperState()
        XCTAssertEqual(shape(&state, settings: settings, time: 1).pressure, 0)
        XCTAssertEqual(shape(&state, settings: settings, time: 1.1).pressure, 0.5)
    }
    func testTaperCombinesCurveAndSharesEntryAcrossMouseAndTabletPackets() throws {
        var p = profile(); p.taper.entryEnabled = true
        var m = processor(p); m.process(try proximity())
        let down = try point(0.5, type: .leftMouseDown); down.timestamp = 1_000_000_000; m.process(down)
        XCTAssertEqual(down.getDoubleValueField(.mouseEventPressure), 0)
        let companion = try point(0.5); companion.timestamp = down.timestamp; m.process(companion)
        XCTAssertEqual(companion.getDoubleValueField(.tabletEventPointPressure), 0)
        let drag = try point(0.5, type: .leftMouseDragged); drag.timestamp = 1_030_000_000
        drag.location.x += 6; m.process(drag)
        XCTAssertEqual(drag.getDoubleValueField(.mouseEventPressure), 0.4, accuracy: 0.005)
        XCTAssertEqual(drag.getDoubleValueField(.tabletEventPointPressure), 0.4, accuracy: 0.005)
        XCTAssertEqual(m.snapshot.diagnostics.last?.taper?.entryFactor ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(drag.timestamp, 1_030_000_000)
    }
    func testTaperSettingsLatchAndDisablingImmediatelyRestoresPressure() throws {
        var p = profile(); p.taper.entryEnabled = true
        var m = processor(p); m.process(try proximity())
        let down = try point(0.5); down.timestamp = 1_000_000_000; m.process(down)
        p.taper.entryDistance = 1; p.taper.entryDurationMS = 10; m.setProfiles([p])
        let held = try point(0.5); held.timestamp = 1_030_000_000; m.process(held)
        XCTAssertEqual(held.getDoubleValueField(.tabletEventPointPressure), 0.4, accuracy: 0.005)
        m.setProfiles([]); let disabled = try point(0.5); m.process(disabled)
        XCTAssertEqual(disabled.getDoubleValueField(.tabletEventPointPressure), 0.5, accuracy: 0.005)
    }
    func testTaperStateDoesNotMixDevicesAndResetsOnNewStroke() throws {
        var p = profile(); p.taper.entryEnabled = true
        var m = processor(p); m.process(try proximity()); m.process(try proximity(id: 18))
        let first = try point(0.5); first.timestamp = 1_000_000_000; m.process(first)
        let second = try point(0.5, id: 18); second.timestamp = 1_030_000_000; m.process(second)
        XCTAssertEqual(second.getDoubleValueField(.tabletEventPointPressure), 0)
        m.process(try point(0)); let next = try point(0.5); next.timestamp = 2_000_000_000; m.process(next)
        XCTAssertEqual(next.getDoubleValueField(.tabletEventPointPressure), 0)
        m.process(try proximity(entering: false)); m.process(try proximity(id: 19))
        let reconnected = try point(0.5, id: 19); m.process(reconnected)
        XCTAssertEqual(reconnected.getDoubleValueField(.tabletEventPointPressure), 0)
    }
    func testTaperDiagnosticsAreExportedWithoutChangingNSEventStream() throws {
        var p = profile(); p.taper.entryEnabled = true
        var m = processor(p); m.process(try proximity()); m.process(try point(0.0784))
        let log = PenLogDocument(store: PenStore(), interactions: PencilInteractionStats(), isMonitoring: true, profiles: [p], mapping: m.snapshot)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: log.jsonData()) as? [String: Any])
        let mapping = try XCTUnwrap(object["mapping"] as? [String: Any])
        let events = try XCTUnwrap(mapping["diagnostics"] as? [[String: Any]])
        let taper = try XCTUnwrap(events.first?["taper"] as? [String: Any])
        XCTAssertEqual(taper["entryFactor"] as? Double, 0)
        XCTAssertEqual(events.first?["outputPressure"] as? Double, 0)
        XCTAssertTrue(log.events.isEmpty)
    }

    private func bufferedProfile() -> PressureProfile {
        var p = profile(); p.taper.exitEnabled = true; return p
    }
    private func queue(_ event: CGEvent, processor: inout PressureMappingProcessor, buffer: inout BufferedPenEvents,
                       now: Double) throws -> PenBufferAction {
        let original = try XCTUnwrap(event.copy())
        let result = processor.process(event, recordDiagnostic: false)
        return buffer.accept(event, original: original, result: result, now: now)
    }
    private func timedPoint(_ p: Double, time: Double, type: CGEventType = .leftMouseDragged, id: Int64 = 17,
                            pid: Int64 = 42, pen: Bool = true) throws -> CGEvent {
        let e = try point(p, id: id, pid: pid, type: type, pen: pen)
        e.timestamp = UInt64((time*1_000_000_000).rounded()); return e
    }
    func testBufferedExitDelaysAndFadesConstantPressureBeforeSuddenLiftOff() throws {
        var m = processor(bufferedProfile()); m.process(try proximity()); var buffer = BufferedPenEvents()
        for (p,t,type): (Double,Double,CGEventType) in [(0.5,1,.leftMouseDown),(0.5,1.03,.leftMouseDragged),(0,1.06,.leftMouseUp)] {
            let action = try queue(timedPoint(p,time:t,type:type),processor:&m,buffer:&buffer,now:t)
            XCTAssertTrue(action.suppress); XCTAssertTrue(action.output.isEmpty)
        }
        XCTAssertTrue(m.snapshot.diagnostics.isEmpty)
        XCTAssertTrue(buffer.drain(now:1.059).isEmpty)
        let start = buffer.drain(now:1.061)
        XCTAssertEqual(start.count,1); XCTAssertEqual(start[0].event.type,.leftMouseDown)
        XCTAssertEqual(start[0].event.getDoubleValueField(.mouseEventPressure),0.8,accuracy:0.005)
        let tail = buffer.drain(now:1.121)
        XCTAssertEqual(tail.map { $0.event.type },[.leftMouseDragged,.leftMouseUp])
        XCTAssertEqual(tail[0].event.getDoubleValueField(.mouseEventPressure),0.4,accuracy:0.005)
        XCTAssertEqual(tail[0].diagnostic?.taper?.exitFactor ?? -1,0.5,accuracy:1e-9)
        XCTAssertEqual(tail[1].event.getDoubleValueField(.mouseEventPressure),0)
        XCTAssertEqual(buffer.count,0)
    }
    func testBufferedExitLeavesAlreadyDeliveredPrefixUnchanged() throws {
        var m = processor(bufferedProfile()); m.process(try proximity()); var buffer = BufferedPenEvents()
        _ = try queue(timedPoint(0.5,time:1,type:.leftMouseDown),processor:&m,buffer:&buffer,now:1)
        let prefix = buffer.drain(now:1.061)
        XCTAssertEqual(prefix.count,1); buffer.didDeliver(prefix[0])
        _ = try queue(timedPoint(0.5,time:1.08),processor:&m,buffer:&buffer,now:1.08)
        _ = try queue(timedPoint(0,time:1.1,type:.leftMouseUp),processor:&m,buffer:&buffer,now:1.1)
        XCTAssertEqual(prefix[0].event.getDoubleValueField(.mouseEventPressure),0.8,accuracy:0.005)
        let tail = buffer.drain(now:1.2)
        XCTAssertLessThan(tail[0].event.getDoubleValueField(.mouseEventPressure),0.3)
    }
    func testBufferedPlainMouseUpFollowsDelayedDownAndEndsTail() throws {
        var m = processor(bufferedProfile()); m.process(try proximity()); var buffer = BufferedPenEvents()
        _ = try queue(timedPoint(0.5,time:1,type:.leftMouseDown),processor:&m,buffer:&buffer,now:1)
        let up = try timedPoint(0,time:1.03,type:.leftMouseUp,pen:false)
        XCTAssertTrue(try queue(up,processor:&m,buffer:&buffer,now:1.03).suppress)
        let output = buffer.drain(now:1.2)
        XCTAssertEqual(output.map { $0.event.type },[.leftMouseDown,.leftMouseUp])
        XCTAssertLessThan(output[0].event.getDoubleValueField(.mouseEventPressure),0.8)
    }
    func testBufferedEventsKeepCoordinatesTimestampsFlagsAndTarget() throws {
        var m = processor(bufferedProfile()); m.process(try proximity()); var buffer = BufferedPenEvents()
        let event = try timedPoint(0.5,time:1,type:.leftMouseDown)
        event.flags = [.maskShift]
        _ = try queue(event,processor:&m,buffer:&buffer,now:1)
        let output = try XCTUnwrap(buffer.drain(now:1.1).first?.event)
        XCTAssertEqual(output.location,CGPoint(x:120,y:200)); XCTAssertEqual(output.timestamp,1_000_000_000)
        XCTAssertEqual(output.flags,[.maskShift]); XCTAssertEqual(output.getIntegerValueField(.eventTargetUnixProcessID),42)
        XCTAssertEqual(output.getIntegerValueField(.tabletEventDeviceID),17)
    }
    func testBufferedCancellationRestoresPendingRawPressureAndReleasesButton() throws {
        var m = processor(bufferedProfile()); m.process(try proximity()); var buffer = BufferedPenEvents()
        _ = try queue(timedPoint(0.5,time:1,type:.leftMouseDown),processor:&m,buffer:&buffer,now:1)
        _ = try queue(timedPoint(0.5,time:1.03),processor:&m,buffer:&buffer,now:1.03)
        let output = buffer.cancel()
        XCTAssertEqual(output.map { $0.event.type },[.leftMouseDown,.leftMouseDragged,.leftMouseUp])
        XCTAssertEqual(output[0].event.getDoubleValueField(.mouseEventPressure),0.5,accuracy:0.005)
        XCTAssertEqual(output.last?.event.getDoubleValueField(.mouseEventPressure),0)
        XCTAssertEqual(output.last?.event.getIntegerValueField(.eventTargetUnixProcessID),42)
        XCTAssertEqual(buffer.count,0); XCTAssertTrue(buffer.cancel().isEmpty)
    }
    func testCancellationReleasesAlreadyPostedDownWithoutDuplicatingExistingUp() throws {
        for ended in [false,true] {
            var m = processor(bufferedProfile()); m.process(try proximity()); var buffer = BufferedPenEvents()
            _ = try queue(timedPoint(0.5,time:1,type:.rightMouseDown),processor:&m,buffer:&buffer,now:1)
            let down = try XCTUnwrap(buffer.drain(now:1.061).first); buffer.didDeliver(down)
            if ended { _ = try queue(timedPoint(0,time:1.07,type:.rightMouseUp),processor:&m,buffer:&buffer,now:1.07) }
            let output = buffer.cancel()
            XCTAssertEqual(output.filter { $0.event.type == .rightMouseUp }.count,1)
        }
    }
    func testKeyboardBoundaryDrainsInOrderAndBypassesRemainingStroke() throws {
        var m = processor(bufferedProfile()); m.process(try proximity()); var buffer = BufferedPenEvents()
        _ = try queue(timedPoint(0.5,time:1,type:.leftMouseDown),processor:&m,buffer:&buffer,now:1)
        let key = try XCTUnwrap(CGEvent(source:nil)); key.type = .keyDown
        let action = try queue(key,processor:&m,buffer:&buffer,now:1.02)
        XCTAssertTrue(action.suppress); XCTAssertEqual(action.output.map { $0.event.type },[.leftMouseDown,.keyDown])
        for packet in action.output { buffer.didDeliver(packet) }
        let drag = try timedPoint(0.5,time:1.03)
        XCTAssertFalse(try queue(drag,processor:&m,buffer:&buffer,now:1.03).suppress)
        XCTAssertEqual(buffer.count,0)
    }
    func testBufferCapacityDrainsInsteadOfLosingButtonEvents() throws {
        var m = processor(bufferedProfile()); m.process(try proximity()); var buffer = BufferedPenEvents()
        var last = PenBufferAction()
        for i in 0..<BufferedPenEvents.limit {
            last = try queue(timedPoint(0.5,time:1,type:i == 0 ? .leftMouseDown : .leftMouseDragged),processor:&m,buffer:&buffer,now:1)
        }
        XCTAssertEqual(last.output.count,BufferedPenEvents.limit)
        XCTAssertEqual(last.output.first?.event.type,.leftMouseDown)
        XCTAssertEqual(buffer.count,0)
    }
    func testBufferDoesNotCaptureUnmatchedDevicesOrApplications() throws {
        var m = processor(bufferedProfile()); m.process(try proximity()); var buffer = BufferedPenEvents()
        for (id,pid): (Int64,Int64) in [(18,42),(17,43),(17,0)] {
            let e = try timedPoint(0.5,time:1,type:.leftMouseDown,id:id,pid:pid)
            XCTAssertFalse(try queue(e,processor:&m,buffer:&buffer,now:1).suppress)
            XCTAssertEqual(e.getDoubleValueField(.mouseEventPressure),0.5,accuracy:0.005)
        }
        XCTAssertEqual(buffer.count,0)
    }
    func testBufferIsolatesDevicesAndPreservesArrivalOrderAcrossDelays() throws {
        let p = bufferedProfile()
        var m = processor(p); m.process(try proximity()); m.process(try proximity(id:18)); var buffer = BufferedPenEvents()
        _ = try queue(timedPoint(0.5,time:1,type:.leftMouseDown),processor:&m,buffer:&buffer,now:1)
        _ = try queue(timedPoint(0.5,time:1.01,type:.leftMouseDown,id:18),processor:&m,buffer:&buffer,now:1.01)
        _ = try queue(timedPoint(0,time:1.02,type:.leftMouseUp),processor:&m,buffer:&buffer,now:1.02)
        let output = buffer.drain(now:1.2)
        XCTAssertEqual(output.map { $0.route.deviceID },[17,18,17])
        XCTAssertEqual(output[1].event.getDoubleValueField(.mouseEventPressure),0.8,accuracy:0.005)
        XCTAssertLessThan(output[0].event.getDoubleValueField(.mouseEventPressure),0.3)
    }

    func testZeroTabletPacketDoesNotLetLaterPlainUpOvertakeQueuedDown() throws {
        var m = processor(bufferedProfile()); m.process(try proximity()); var buffer = BufferedPenEvents()
        _ = try queue(timedPoint(0.5,time:1,type:.leftMouseDown),processor:&m,buffer:&buffer,now:1)
        _ = try queue(timedPoint(0,time:1.01,type:.tabletPointer),processor:&m,buffer:&buffer,now:1.01)
        let delivered = buffer.drain(now:1.08)
        for packet in delivered { buffer.didDeliver(packet) }
        let up = try timedPoint(0,time:1.09,type:.leftMouseUp,pen:false)
        XCTAssertTrue(try queue(up,processor:&m,buffer:&buffer,now:1.09).suppress)
        XCTAssertTrue(buffer.drain(now:1.14).isEmpty)
        XCTAssertEqual(buffer.drain(now:1.16).last?.event.type,.leftMouseUp)
    }
    func testProximityExitAddsReleaseWhenHardwareOmitsMouseUp() throws {
        var m = processor(bufferedProfile()); m.process(try proximity()); var buffer = BufferedPenEvents()
        _ = try queue(timedPoint(0.5,time:1,type:.leftMouseDown),processor:&m,buffer:&buffer,now:1)
        let exit = try proximity(entering:false); exit.timestamp = 1_020_000_000
        XCTAssertTrue(try queue(exit,processor:&m,buffer:&buffer,now:1.02).suppress)
        let output = buffer.drain(now:1.2)
        XCTAssertEqual(output.map { $0.event.type },[.leftMouseDown,.leftMouseUp,.tabletProximity])
        XCTAssertEqual(output[1].event.getDoubleValueField(.mouseEventPressure),0)
    }
    func testOtherButtonNumberIsPreservedByCancellationRelease() throws {
        var m = processor(bufferedProfile()); m.process(try proximity()); var buffer = BufferedPenEvents()
        let down = try timedPoint(0.5,time:1,type:.otherMouseDown)
        down.setIntegerValueField(.mouseEventButtonNumber,value:7)
        _ = try queue(down,processor:&m,buffer:&buffer,now:1)
        let output = buffer.cancel()
        XCTAssertEqual(output.last?.event.type,.otherMouseUp)
        XCTAssertEqual(output.last?.event.getIntegerValueField(.mouseEventButtonNumber),7)
    }
    func testTargetChangeFlushesAndReleasesBeforeForwardingNewTargetEvent() throws {
        var m = processor(bufferedProfile()); m.process(try proximity()); var buffer = BufferedPenEvents()
        _ = try queue(timedPoint(0.5,time:1,type:.leftMouseDown),processor:&m,buffer:&buffer,now:1)
        let other = try timedPoint(0.5,time:1.02,pid:43)
        let action = try queue(other,processor:&m,buffer:&buffer,now:1.02)
        XCTAssertTrue(action.suppress)
        XCTAssertEqual(action.output.map { $0.event.type },[.leftMouseDown,.leftMouseUp,.leftMouseDragged])
        XCTAssertEqual(action.output.last?.event.getIntegerValueField(.eventTargetUnixProcessID),43)
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

@MainActor private final class MappingPanelBackend: EventMonitoring {
    let events: [NSEvent]
    init(event: NSEvent) { events = [event] }
    init(events: [NSEvent]) { self.events = events }
    func start(handler: @escaping @MainActor (NSEvent, EventSource) -> Void) -> MonitorInstallation {
        for event in events { handler(event, .local) }
        return MonitorInstallation(local: true, global: false)
    }
    func stop() { }
}

extension PressureMappingTests {
    func testComponentOverridesResolveIndependentlyAndFollowDefaults() throws {
        var base = PressureConfiguration(curve: .light)
        base.taper.entryEnabled = true; base.taper.exitEnabled = true
        var rule = ApplicationPressureRule(bundleID: "ps", name: "PS")
        rule.setOverride(.smoothing, enabled: true, base: base)
        rule.configuration.smoothing.enabled = true
        XCTAssertEqual(rule.effectiveOverrides, [.smoothing])
        XCTAssertEqual(rule.resolved(base: base).curve, .light)
        XCTAssertTrue(rule.resolved(base: base).taper.entryEnabled)
        base.curve = .linear; base.taper.entryDurationMS = 120
        XCTAssertEqual(rule.resolved(base: base).curve, .linear)
        XCTAssertEqual(rule.resolved(base: base).taper.entryDurationMS, 120)
        rule.setOverride(.entry, enabled: true, base: base)
        rule.configuration.taper.entryDurationMS = 90
        base.taper.entryDurationMS = 150; base.taper.exitDurationMS = 100
        XCTAssertEqual(rule.resolved(base: base).taper.entryDurationMS, 90)
        XCTAssertEqual(rule.resolved(base: base).taper.exitDurationMS, 100)
        rule.setOverride(.entry, enabled: false, base: base)
        XCTAssertEqual(rule.resolved(base: base).taper.entryDurationMS, 150)
        rule.setOverride(.entry, enabled: true, base: base)
        XCTAssertEqual(rule.configuration.taper.entryDurationMS, 150, "Re-enabling copies the latest inherited value")
        rule.setOverride(.curve, enabled: true, base: base)
        rule.configuration.curve = .light
        rule.setOverride(.exit, enabled: true, base: base)
        rule.configuration.taper.exitEnabled = false
        XCTAssertEqual(rule.resolved(base: base).curve, .light)
        XCTAssertFalse(rule.resolved(base: base).taper.exitEnabled)
        XCTAssertTrue(rule.summary.contains("轨迹平滑"))
    }

    func testLegacyConfigurationDecodesAndMigratesComponentFlagsWithoutChangingValues() throws {
        var p = deviceProfile()
        p.applicationRules?[0].mode = .custom
        p.applicationRules?[0].configuration = .init(curve: .light, taper: .init(entryEnabled: true, exitEnabled: true))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        object.removeValue(forKey: "smoothing")
        var rules = try XCTUnwrap(object["applicationRules"] as? [[String: Any]])
        for i in rules.indices {
            rules[i].removeValue(forKey: "overrides")
            var c = rules[i]["configuration"] as! [String: Any]; c.removeValue(forKey: "smoothing"); rules[i]["configuration"] = c
        }
        object["applicationRules"] = rules
        let old = try JSONDecoder().decode(PressureProfile.self, from: JSONSerialization.data(withJSONObject: object))
        var defaults = MappingDefaults(); defaults.schemaVersion = 2
        let result = defaults.migrating([old])
        XCTAssertEqual(result.defaults.schemaVersion, 3)
        let custom = try XCTUnwrap(result.profiles[0].applicationRules?.first)
        XCTAssertEqual(custom.overrides, [.curve, .entry, .exit])
        XCTAssertEqual(custom.configuration.curve, .light)
        XCTAssertTrue(custom.configuration.taper.entryEnabled); XCTAssertTrue(custom.configuration.taper.exitEnabled)
        XCTAssertFalse(custom.resolved(base: .init()).smoothing.enabled)
        XCTAssertEqual(result.profiles[0].applicationRules?[1].overrides, [])
        XCTAssertEqual(result.defaults.migrating(result.profiles).profiles, result.profiles)
        XCTAssertEqual(try JSONDecoder().decode(PressureProfile.self, from: JSONEncoder().encode(result.profiles[0])), result.profiles[0])
        var bad = PressureConfiguration(); bad.smoothing.strength = .nan; XCTAssertFalse(bad.isValid)
        bad.smoothing.strength = 1.1; XCTAssertFalse(bad.isValid)
    }

    func testOneEuroSmoothsJitterAdaptsToSpeedAndHandlesTimestamps() {
        let settings = TrajectorySmoothingSettings(enabled: true, strength: 0.7)
        var filter = TrajectorySmoothingState()
        var inputEnergy = 0.0, outputEnergy = 0.0
        for i in 0..<240 {
            let x = i == 0 ? 0.0 : (i.isMultiple(of: 2) ? 1.0 : -1.0)
            let value = filter.apply(screen: .init(x: x, y: 0), tablet: .init(x: x*10, y: 0), timestamp: Double(i)/240, settings: settings)
            inputEnergy += x*x; outputEnergy += value.screen.x*value.screen.x
            XCTAssertEqual(value.tablet.x, value.screen.x*10, accuracy: 1e-9)
        }
        XCTAssertLessThan(outputEnergy, inputEnergy*0.2)
        let last = filter.screen
        XCTAssertEqual(filter.apply(screen: .init(x: 999,y: 0), tablet: .zero, timestamp: 0, settings: settings).screen, last)
        XCTAssertEqual(filter.apply(screen: .init(x: 999,y: 0), tablet: .zero, timestamp: 1, settings: settings, ending: true).screen, last)
        let reset = filter.apply(screen: .init(x: 50,y: 0), tablet: .init(x: 500,y: 0), timestamp: 2, settings: settings)
        XCTAssertEqual(reset.screen.x, 50)
        var adaptive = TrajectorySmoothingState(), slow = TrajectorySmoothingState()
        for i in 0..<100 {
            let t = Double(i)*0.006 + (i.isMultiple(of: 2) ? 0 : 0.001)
            _ = adaptive.apply(screen: .init(x: Double(i)*10,y: 0), tablet: .zero, timestamp: t, settings: settings)
            _ = slow.apply(screen: .init(x: Double(i)*0.01,y: 0), tablet: .zero, timestamp: t, settings: settings)
        }
        XCTAssertLessThan((990-adaptive.screen.x)/990, (0.99-slow.screen.x)/0.99)
        var bypass = TrajectorySmoothingState()
        for config in [TrajectorySmoothingSettings(), .init(enabled: true, strength: 0)] {
            XCTAssertEqual(bypass.apply(screen: .init(x: 20,y: 5), tablet: .zero, timestamp: 1, settings: config).screen.x, 20)
        }
    }

    private func trajectoryPoint(_ x: Double, time: Double, pressure: Double = 0.5, type: CGEventType = .leftMouseDragged, id: Int64 = 17, pid: Int64 = 42, pen: Bool = true) throws -> CGEvent {
        let e = try point(pressure, id: id, pid: pid, type: type, pen: pen)
        e.timestamp = UInt64((time*1_000_000_000).rounded()); e.location = .init(x: x, y: 100)
        e.setIntegerValueField(.tabletEventPointX, value: Int64(x*100)); e.setIntegerValueField(.tabletEventPointY, value: 10_000)
        return e
    }
    private func smoothingProfile() -> PressureProfile {
        var p = profile(curve: .linear); p.smoothing = .init(enabled: true, strength: 0.7); return p
    }

    func testQuartzSmoothingKeepsCoordinateSpacesPressureAndReleaseCoherent() throws {
        var m = processor(smoothingProfile()); m.process(try proximity())
        let down = try trajectoryPoint(0, time: 1, type: .leftMouseDown); m.process(down)
        XCTAssertEqual(down.location.x, 0)
        let drag = try trajectoryPoint(10, time: 1.005); m.process(drag)
        XCTAssertGreaterThan(drag.location.x, 0); XCTAssertLessThan(drag.location.x, 10)
        XCTAssertEqual(Double(drag.getIntegerValueField(.tabletEventPointX)), drag.location.x*100, accuracy: 0.51)
        XCTAssertEqual(drag.getIntegerValueField(.mouseEventDeltaX), Int64(drag.location.x.rounded()))
        XCTAssertEqual(drag.getDoubleValueField(.mouseEventPressure), down.getDoubleValueField(.mouseEventPressure))
        XCTAssertEqual(drag.getDoubleValueField(.tabletEventTiltX), down.getDoubleValueField(.tabletEventTiltX))
        XCTAssertEqual(drag.getDoubleValueField(.tabletEventRotation), down.getDoubleValueField(.tabletEventRotation))
        XCTAssertEqual(drag.timestamp, 1_005_000_000)
        // Standalone zero can precede the companion mouse-up.
        m.process(try trajectoryPoint(20, time: 1.008, pressure: 0, type: .tabletPointer))
        let up = try trajectoryPoint(25, time: 1.01, pressure: 0, type: .leftMouseUp); m.process(up)
        XCTAssertEqual(up.location.x, 25, "Release coordinates must retain original delivery metadata")
        XCTAssertEqual(up.getDoubleValueField(.mouseEventPressure), 0)
        XCTAssertEqual(up.getIntegerValueField(.mouseEventDeltaX), 0)
        let next = try trajectoryPoint(80, time: 2, type: .leftMouseDown); m.process(next)
        XCTAssertEqual(next.location.x, 80)
        XCTAssertNotNil(m.snapshot.diagnostics.first?.eventType)
        XCTAssertNotNil(m.snapshot.diagnostics.first?.smoothing)
        let document = PenLogDocument(store: .init(), interactions: .init(), isMonitoring: true, mapping: m.snapshot)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: document.jsonData()) as? [String: Any])
        let mapping = try XCTUnwrap(json["mapping"] as? [String: Any])
        let diagnostics = try XCTUnwrap(mapping["diagnostics"] as? [[String: Any]])
        XCTAssertEqual((diagnostics.last?["outputPosition"] as? [String: Double])?["x"], 80)
    }

    func testSmoothingPassthroughLatchDisableAndProximityReset() throws {
        var m = processor(smoothingProfile()); m.process(try proximity()); m.process(try proximity(id: 18, vendor: 1386))
        for event in [try trajectoryPoint(10,time: 1,id: 18), try trajectoryPoint(10,time: 1,pid: 43),
                      try trajectoryPoint(10,time: 1,pen: false), try trajectoryPoint(10,time: 1,type: .rightMouseDown),
                      try trajectoryPoint(10,time: 1,type: .mouseMoved)] {
            let original = event.location; m.process(event); XCTAssertEqual(event.location, original)
        }
        m.process(try trajectoryPoint(10,time: 1.5,pressure: 0,type: .leftMouseUp))
        // Explicit new contact after the passthrough decisions above.
        m.process(try trajectoryPoint(0,time: 2,type: .leftMouseDown))
        m.setProfiles([profile(curve: .linear)])
        let held = try trajectoryPoint(10,time: 2.005); m.process(held)
        XCTAssertLessThan(held.location.x, 10, "Settings remain latched until release")
        m.setProfiles([])
        let disabled = try trajectoryPoint(20,time: 2.01); m.process(disabled); XCTAssertEqual(disabled.location.x, 20)
        m.setProfiles([smoothingProfile()]); m.process(try proximity(entering: false)); m.process(try proximity())
        let next = try trajectoryPoint(90,time: 3,type: .leftMouseDown); m.process(next); XCTAssertEqual(next.location.x, 90)
    }

    func testSmoothingAndExitQueuePreserveOrderAndCancellationRestoresPositions() throws {
        var p = smoothingProfile(); p.taper.exitEnabled = true; p.taper.entryEnabled = true
        var m = processor(p); m.process(try proximity())
        var queue = BufferedPenEvents()
        var originals: [CGEvent] = []
        for (x,t,type) in [(0.0,1.0,CGEventType.leftMouseDown),(10,1.005,.leftMouseDragged),(20,1.01,.leftMouseUp)] {
            let e = try trajectoryPoint(x,time: t,pressure: type == .leftMouseUp ? 0 : 0.5,type: type)
            let original = try XCTUnwrap(e.copy()); originals.append(original)
            let result = try XCTUnwrap(m.process(e))
            XCTAssertTrue(queue.accept(e, original: original, result: result, now: t).suppress)
        }
        let output = queue.drain(now: 2)
        XCTAssertEqual(output.map(\.event.type), [.leftMouseDown,.leftMouseDragged,.leftMouseUp])
        XCTAssertEqual(output[2].event.location.x, 20)
        XCTAssertEqual(output[2].event.getDoubleValueField(.mouseEventPressure),0)
        XCTAssertEqual(m.snapshot.diagnostics[1].taper?.distance, 10)
        m.process(try proximity())
        let e = try trajectoryPoint(30,time: 3,type: .leftMouseDown), original = try XCTUnwrap(try trajectoryPoint(30,time: 3,type: .leftMouseDown).copy())
        _ = queue.accept(e, original: original, result: m.process(e), now: 3)
        XCTAssertEqual(queue.cancel().first?.event.location, original.location)
    }
}

extension PressureMappingTests {
    func testSmoothingStatesAreIndependentAcrossDevicesAndPlainReleaseIsUntouched() throws {
        var pencil = smoothingProfile(), wacom = smoothingProfile()
        pencil.taper.entryEnabled = false
        wacom.device = PenIdentity(key: "v1:model:56a:129a:0:pen", level: .model)
        var m = processor(pencil); m.setProfiles([pencil,wacom])
        m.process(try proximity()); m.process(try proximity(id: 18,vendor: 1386))
        m.process(try trajectoryPoint(0,time: 1,type: .leftMouseDown))
        let tabletDown = try trajectoryPoint(500,time: 1,type: .leftMouseDown,id: 18); m.process(tabletDown)
        XCTAssertEqual(tabletDown.location.x, 500)
        let pencilDrag = try trajectoryPoint(10,time: 1.005); m.process(pencilDrag)
        let tabletDrag = try trajectoryPoint(510,time: 1.005,id: 18); m.process(tabletDrag)
        XCTAssertEqual(tabletDrag.location.x-pencilDrag.location.x, 500, accuracy: 1e-9)
        m.process(try proximity(id: 18,entering: false,vendor: 1386))
        m.process(try trajectoryPoint(20,time: 1.01,pressure: 0,type: .tabletPointer))
        let plainUp = try trajectoryPoint(30,time: 1.015,pressure: 0,type: .leftMouseUp,pen: false)
        m.process(plainUp)
        XCTAssertEqual(plainUp.location.x, 30)
        // With no known pending pen release an ordinary click remains untouched.
        let mouseUp = try trajectoryPoint(80,time: 2,pressure: 0,type: .leftMouseUp,pen: false)
        m.process(mouseUp); XCTAssertEqual(mouseUp.location.x,80)
    }

    func testCancelledSmoothedQueueRestoresCoordinatesAndDiagnostic() throws {
        var p = smoothingProfile(); p.taper.exitEnabled = true
        var m = processor(p); m.process(try proximity())
        var queue = BufferedPenEvents()
        for (x,t,type) in [(0.0,1.0,CGEventType.leftMouseDown),(10,1.005,.leftMouseDragged)] {
            let e = try trajectoryPoint(x,time: t,type: type), original = try XCTUnwrap(try trajectoryPoint(x,time: t,type: type).copy())
            let result = m.process(e)
            XCTAssertTrue(queue.accept(e,original: original,result: result,now: t).suppress)
        }
        let cancelled = queue.cancel()
        XCTAssertEqual(cancelled[1].event.location.x,10)
        XCTAssertEqual(cancelled[1].event.getIntegerValueField(.tabletEventPointX),1000)
        XCTAssertEqual(cancelled[1].diagnostic?.inputPosition,cancelled[1].diagnostic?.outputPosition)
        XCTAssertEqual(cancelled[1].diagnostic?.smoothing?.enabled,false)
        XCTAssertEqual(cancelled[1].diagnostic?.smoothing?.inputTablet,cancelled[1].diagnostic?.smoothing?.outputTablet)
    }
}

extension PressureMappingTests {
    func testSmoothingDoesNotRewriteMouseBoundaryPayloads() throws {
        var m = processor(smoothingProfile()); m.process(try proximity())
        let preserved: [CGEventField] = [.mouseEventSubtype,.mouseEventButtonNumber,.mouseEventClickState,
            .mouseEventNumber,.mouseEventDeltaX,.mouseEventDeltaY,.tabletEventPointX,.tabletEventPointY,
            .tabletEventPointZ,.tabletEventPointButtons,.tabletEventDeviceID,.tabletEventTiltX,
            .tabletEventTiltY,.tabletEventRotation,.tabletEventTangentialPressure,
            .eventTargetUnixProcessID,.eventSourceUnixProcessID]
        for (x,t,type) in [(0.0,1.0,CGEventType.leftMouseDown),(50,1.01,.leftMouseUp)] {
            let appKit = try XCTUnwrap(NSEvent.mouseEvent(with: type == .leftMouseDown ? .leftMouseDown : .leftMouseUp,
                location: .init(x: x,y: 100), modifierFlags: [.shift], timestamp: t,
                windowNumber: 123, context: nil,eventNumber: 77,clickCount: 1,pressure: type == .leftMouseDown ? 0.5 : 0))
            let e = try XCTUnwrap(appKit.cgEvent?.copy())
            e.setIntegerValueField(.mouseEventSubtype,value: 1)
            e.setIntegerValueField(.tabletEventDeviceID,value: 17)
            e.setIntegerValueField(.eventTargetUnixProcessID,value: 42)
            e.setIntegerValueField(.tabletEventPointX,value: Int64(x*100))
            e.setIntegerValueField(.tabletEventPointY,value: 10000)
            e.setIntegerValueField(.tabletEventPointButtons,value: type == .leftMouseDown ? 1 : 0)
            e.setIntegerValueField(.mouseEventDeltaX,value: 27)
            e.setIntegerValueField(.mouseEventDeltaY,value: -13)
            e.setDoubleValueField(.tabletEventPointPressure,value: type == .leftMouseDown ? 0.5 : 0)
            let location = e.location, flags = e.flags, timestamp = e.timestamp
            let values = preserved.map { e.getDoubleValueField($0) }
            let before = try XCTUnwrap(NSEvent(cgEvent: e))
            m.process(e)
            XCTAssertEqual(e.location,location); XCTAssertEqual(e.flags,flags); XCTAssertEqual(e.timestamp,timestamp)
            XCTAssertEqual(preserved.map { e.getDoubleValueField($0) },values)
            let after = try XCTUnwrap(NSEvent(cgEvent: e))
            XCTAssertEqual(after.type,before.type); XCTAssertEqual(after.windowNumber,before.windowNumber)
            XCTAssertEqual(after.eventNumber,before.eventNumber); XCTAssertEqual(after.clickCount,before.clickCount)
            XCTAssertEqual(after.buttonMask,before.buttonMask); XCTAssertEqual(after.deviceID,before.deviceID)
            if type == .leftMouseDown {
                let drag = try trajectoryPoint(10,time: t+0.005); m.process(drag)
                XCTAssertLessThan(drag.location.x,10)
            }
        }
    }
}

extension PressureMappingTests {
    func testProductionSmoothingIsQuarantinedWithoutChangingPressureMapping() throws {
        var p = smoothingProfile(); p.curve = .light
        var m = PressureMappingProcessor() // Exact production defaults, no experimental coordinate writes.
        m.applications = [42: "com.adobe.Photoshop"]; m.setProfiles([p]); m.process(try proximity())
        for (x,t,type) in [(0.0,1.0,CGEventType.leftMouseDown),(10,1.005,.leftMouseDragged),(30,1.01,.leftMouseUp)] {
            let e = try trajectoryPoint(x,time: t,pressure: type == .leftMouseUp ? 0 : 0.5,type: type)
            e.setIntegerValueField(.mouseEventDeltaX,value: 24)
            e.setIntegerValueField(.mouseEventDeltaY,value: -31)
            let original = try XCTUnwrap(e.copy())
            m.process(e)
            XCTAssertEqual(e.location,original.location)
            for field: CGEventField in [.mouseEventDeltaX,.mouseEventDeltaY,.tabletEventPointX,.tabletEventPointY,.tabletEventPointButtons,.mouseEventNumber] {
                XCTAssertEqual(e.getIntegerValueField(field),original.getIntegerValueField(field))
            }
            XCTAssertEqual(e.getDoubleValueField(.tabletEventPointPressure),type == .leftMouseUp ? 0 : 0.8,accuracy: 0.005)
            XCTAssertNotNil(m.snapshot.diagnostics.last?.smoothingBypassReason)
            XCTAssertNil(m.snapshot.diagnostics.last?.smoothing)
        }
        XCTAssertEqual(m.snapshot.coordinateProbes?.count,3)
        let probe = try XCTUnwrap(m.snapshot.coordinateProbes?.first)
        let captured = try XCTUnwrap(CGEvent(withDataAllocator: nil, data: probe.eventData as CFData))
        XCTAssertEqual(captured.type,.leftMouseDown)
        XCTAssertEqual(captured.getDoubleValueField(.tabletEventPointPressure),0.5,accuracy: 0.005,"Capture precedes pressure processing")
        XCTAssertEqual(captured.location.x,0)
        let document = PenLogDocument(store: .init(),interactions: .init(),isMonitoring: true,mapping: m.snapshot)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: document.jsonData()) as? [String: Any])
        let mapping = try XCTUnwrap(json["mapping"] as? [String: Any])
        XCTAssertEqual((mapping["coordinateProbes"] as? [Any])?.count,3)
    }

    func testCoordinateProbesAreSparseBoundedAndExcludeUnmatchedInput() throws {
        var m = PressureMappingProcessor();m.applications = [42: "com.adobe.Photoshop",43: "other.app"]
        m.setProfiles([smoothingProfile()]);m.process(try proximity())
        m.process(try trajectoryPoint(0,time: 1,type: .leftMouseDown,pid: 43))
        m.process(try trajectoryPoint(0,time: 1.01,pressure: 0,type: .leftMouseUp,pid: 43))
        m.process(try trajectoryPoint(0,time: 1.02,pen: false))
        XCTAssertNil(m.snapshot.coordinateProbes)
        for i in 0..<100 {
            m.process(try trajectoryPoint(Double(i),time: 2+Double(i)*0.005))
        }
        XCTAssertEqual(m.snapshot.coordinateProbes?.count,1)
        XCTAssertEqual(m.snapshot.coordinateProbes?.first?.eventType,CGEventType.leftMouseDragged.rawValue)
        // Different recognized devices share a fixed total budget, never an unbounded event archive.
        for i in 1...24 {
            let identity = PenIdentity(key: "v1:model:\(String(i,radix:16)):129a:0:pen",level: .model)
            var profile = smoothingProfile();profile.device = identity
            m.setProfiles([profile]);m.process(try proximity(id: Int64(i+100),vendor: Int64(i)))
            m.process(try trajectoryPoint(0,time: 3,type: .leftMouseDown,id: Int64(i+100)))
        }
        XCTAssertEqual(m.snapshot.coordinateProbes?.count,16)
    }
}
