import XCTest
import AppKit
@testable import PenActor

final class PenActorTests: XCTestCase {
    func testIndependentTabletEvents() {
        XCTAssertEqual(TabletEventKind.classify(type: .tabletPoint, subtype: .mouseEvent), .point)
        XCTAssertEqual(TabletEventKind.classify(type: .tabletProximity, subtype: .mouseEvent), .proximity)
    }

    func testTabletSubtypesInAllMouseEventForms() {
        let types: [NSEvent.EventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                        .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                        .otherMouseDown, .otherMouseUp, .otherMouseDragged]
        for type in types {
            XCTAssertEqual(TabletEventKind.classify(type: type, subtype: .tabletPoint), .point)
            XCTAssertEqual(TabletEventKind.classify(type: type, subtype: .tabletProximity), .proximity)
            XCTAssertEqual(TabletEventKind.classify(type: type, subtype: .mouseEvent), .ignored)
        }
    }

    func testNonPenInputCannotMasqueradeAsTablet() {
        for type: NSEvent.EventType in [.pressure, .rotate, .scrollWheel, .keyDown, .directTouch, .changeMode] {
            XCTAssertEqual(TabletEventKind.classify(type: type, subtype: .tabletPoint), .ignored)
        }
    }

    func testPressureAccessValidity() {
        XCTAssertFalse(TabletEventKind.canReadPressure(type: .mouseMoved))
        XCTAssertFalse(TabletEventKind.canReadPressure(type: .tabletProximity))
        XCTAssertFalse(TabletEventKind.canReadPressure(type: .rotate))
        XCTAssertTrue(TabletEventKind.canReadPressure(type: .tabletPoint))
        XCTAssertTrue(TabletEventKind.canReadPressure(type: .leftMouseDragged))
        XCTAssertTrue(TabletEventKind.canReadPressure(type: .leftMouseUp))
    }

    func testDecoderReadsTabletPointFieldsFromQuartzFixture() throws {
        let quartz = try XCTUnwrap(CGEvent(source: nil))
        quartz.type = .tabletPointer
        quartz.setIntegerValueField(.tabletEventDeviceID, value: 17)
        quartz.setIntegerValueField(.tabletEventPointX, value: 1234)
        quartz.setIntegerValueField(.tabletEventPointY, value: 5678)
        quartz.setIntegerValueField(.tabletEventPointZ, value: 12)
        quartz.setIntegerValueField(.tabletEventPointButtons, value: 3)
        quartz.setDoubleValueField(.tabletEventPointPressure, value: 0.6)
        quartz.setDoubleValueField(.tabletEventTiltX, value: -0.3)
        quartz.setDoubleValueField(.tabletEventTiltY, value: 0.4)
        quartz.setDoubleValueField(.tabletEventRotation, value: 32)
        quartz.setDoubleValueField(.tabletEventTangentialPressure, value: -0.2)
        let event = try XCTUnwrap(NSEvent(cgEvent: quartz))
        let decoded = try XCTUnwrap(PenEventDecoder.decode(event, source: .global, foregroundApp: "Fixture"))
        XCTAssertNil(decoded.info)
        XCTAssertNil(decoded.proximity)
        XCTAssertEqual(decoded.deviceID, 17)
        XCTAssertEqual(decoded.source, .global)
        XCTAssertEqual(decoded.typeName, "tabletPoint")
        let sample = try XCTUnwrap(decoded.sample)
        XCTAssertEqual(try XCTUnwrap(sample.pressure), 0.6, accuracy: 0.001)
        XCTAssertEqual(sample.tiltX, -0.3, accuracy: 0.001)
        XCTAssertEqual(sample.tiltY, 0.4, accuracy: 0.001)
        XCTAssertEqual(sample.rotation, 32, accuracy: 0.01)
        XCTAssertEqual(sample.tangentialPressure, -0.2, accuracy: 0.001)
        XCTAssertEqual(sample.absoluteX, 1234)
        XCTAssertEqual(sample.absoluteY, 5678)
        XCTAssertEqual(sample.absoluteZ, 12)
        XCTAssertEqual(sample.buttons, 3)
    }

    func testDecoderReadsOnlyMetadataFromQuartzProximityFixture() throws {
        let quartz = try XCTUnwrap(CGEvent(source: nil))
        quartz.type = .tabletProximity
        let fields: [(CGEventField, Int64)] = [
            (.tabletProximityEventDeviceID, 17), (.tabletProximityEventVendorID, 1386),
            (.tabletProximityEventTabletID, 22), (.tabletProximityEventPointerID, 2),
            (.tabletProximityEventSystemTabletID, 3), (.tabletProximityEventVendorPointerType, 4),
            (.tabletProximityEventVendorPointerSerialNumber, 123), (.tabletProximityEventVendorUniqueID, 456),
            (.tabletProximityEventCapabilityMask, 0x2400), (.tabletProximityEventPointerType, 1),
            (.tabletProximityEventEnterProximity, 1)
        ]
        for (field, value) in fields { quartz.setIntegerValueField(field, value: value) }
        let event = try XCTUnwrap(NSEvent(cgEvent: quartz))
        let decoded = try XCTUnwrap(PenEventDecoder.decode(event, source: .local, foregroundApp: "Fixture"))
        XCTAssertNil(decoded.sample)
        XCTAssertEqual(decoded.proximity, true)
        XCTAssertEqual(decoded.deviceID, 17)
        let info = try XCTUnwrap(decoded.info)
        XCTAssertEqual(info.vendorID, 1386)
        XCTAssertEqual(info.tabletID, 22)
        XCTAssertEqual(info.pointingDeviceID, 2)
        XCTAssertEqual(info.systemTabletID, 3)
        XCTAssertEqual(info.vendorPointingDeviceType, 4)
        XCTAssertEqual(info.serialNumber, 123)
        XCTAssertEqual(info.uniqueID, 456)
        XCTAssertEqual(info.capabilityMask, 0x2400)
        XCTAssertEqual(info.toolType, "笔")
    }

    func testMouseMovedTabletFixtureDoesNotAccessInvalidPressure() throws {
        let quartz = try XCTUnwrap(CGEvent(source: nil))
        quartz.type = .mouseMoved
        quartz.setIntegerValueField(.mouseEventSubtype, value: 1)
        quartz.setIntegerValueField(.tabletEventDeviceID, value: 9)
        let event = try XCTUnwrap(NSEvent(cgEvent: quartz))
        let decoded = try XCTUnwrap(PenEventDecoder.decode(event, source: .local, foregroundApp: "Fixture"))
        XCTAssertEqual(decoded.deviceID, 9)
        XCTAssertEqual(decoded.typeName, "mouseMoved · tabletPoint")
        XCTAssertNotNil(decoded.sample)
        XCTAssertNil(decoded.sample?.pressure)
    }

    func testEditedQuartzPressureReachesNSEventWithoutChangingOtherFields() throws {
        // In-process API feasibility check only: no tap, posting or external app.
        for type: CGEventType in [.tabletPointer, .leftMouseDragged] {
            let original = try XCTUnwrap(CGEvent(source: nil))
            original.type = type
            if type == .leftMouseDragged { original.setIntegerValueField(.mouseEventSubtype, value: 1) }
            original.setDoubleValueField(.tabletEventPointPressure, value: 0.4)
            original.setDoubleValueField(.mouseEventPressure, value: 0.4)
            original.setDoubleValueField(.tabletEventTiltX, value: 0.25)
            original.setIntegerValueField(.tabletEventDeviceID, value: 17)
            original.setIntegerValueField(.tabletEventPointButtons, value: 1)
            let edited = try XCTUnwrap(original.copy())
            edited.setDoubleValueField(.tabletEventPointPressure, value: 0.8)
            if type != .tabletPointer { edited.setDoubleValueField(.mouseEventPressure, value: 0.8) }
            let before = try XCTUnwrap(NSEvent(cgEvent: original))
            let after = try XCTUnwrap(NSEvent(cgEvent: edited))
            XCTAssertEqual(before.pressure, 0.4, accuracy: 0.001)
            XCTAssertEqual(after.pressure, 0.8, accuracy: 0.001)
            XCTAssertEqual(before.deviceID, after.deviceID)
            XCTAssertEqual(before.buttonMask, after.buttonMask)
            XCTAssertEqual(before.tilt.x, after.tilt.x, accuracy: 0.001)
        }
    }

    func testSampleBeforeProximityRetainsMissingMetadata() {
        var store = PenStore()
        store.ingest(event(sample: sample(0)))
        XCTAssertNil(store.selectedDevice?.info)
        XCTAssertNil(store.selectedDevice?.proximity)
        XCTAssertEqual(store.selectedDevice?.lastSampleEvent?.sample?.pressure, 0)
    }

    func testProximityMetadataAssociatesByDeviceID() {
        var store = PenStore()
        store.ingest(event(proximity: true, info: info()))
        store.ingest(event(sample: sample(0.7)))
        XCTAssertEqual(store.selectedDevice?.info, info())
        XCTAssertEqual(store.selectedDevice?.lastSampleEvent?.sample?.pressure, 0.7)
    }

    func testMultipleDevicesDoNotMixSamples() {
        var store = PenStore()
        store.automaticallySwitchDevices = false
        store.ingest(event(id: 1, sample: sample(0.1)))
        store.ingest(event(id: 2, sample: sample(0.9)))
        XCTAssertEqual(store.selectedIdentity, .session(1))
        XCTAssertEqual(store.selectedDevice?.lastSampleEvent?.sample?.pressure, 0.1)
        store.selectedIdentity = .session(2)
        XCTAssertEqual(store.selectedDevice?.lastSampleEvent?.sample?.pressure, 0.9)
    }

    func testProximityExitKeepsHistoricalSample() {
        var store = PenStore()
        store.ingest(event(proximity: true, info: info()))
        store.ingest(event(sample: sample(0.4)))
        store.ingest(event(proximity: false, info: info()))
        XCTAssertEqual(store.selectedDevice?.proximity, false)
        XCTAssertEqual(store.selectedDevice?.lastSampleEvent?.sample?.pressure, 0.4)
        XCTAssertTrue(store.selectedDevice?.status.contains("历史") == true)
    }

    func testReusedDeviceIDStartsNewSession() {
        var store = PenStore()
        store.ingest(event(proximity: true, info: info()))
        store.ingest(event(sample: sample(0.5)))
        store.ingest(event(proximity: true, info: info(serial: 42)))
        XCTAssertEqual(store.selectedDevice?.info?.serialNumber, 42)
        XCTAssertNil(store.selectedDevice?.lastSampleEvent)
        XCTAssertEqual(store.selectedDevice?.history.count, 0)
    }

    func testPressureMissingIsDistinctFromZero() {
        var store = PenStore()
        store.ingest(event(sample: sample(nil)))
        XCTAssertNotNil(store.selectedDevice?.lastSampleEvent?.sample)
        XCTAssertNil(store.selectedDevice?.lastSampleEvent?.sample?.pressure)
        store.ingest(event(sample: sample(0)))
        XCTAssertEqual(store.selectedDevice?.lastSampleEvent?.sample?.pressure, 0)
    }

    func testCapabilityUnknownAndNotDeclaredAreDistinct() {
        XCTAssertEqual(PenCapability.rotation.support(mask: nil), "支持情况未知")
        XCTAssertEqual(PenCapability.rotation.support(mask: 0), "支持情况未知")
        XCTAssertEqual(PenCapability.rotation.support(mask: 0x0400), "驱动未声明支持")
        XCTAssertEqual(PenCapability.rotation.support(mask: 0x2000), "驱动声明支持")
    }

    func testHistoryAndEventBuffersAreBounded() {
        var store = PenStore()
        for index in 0..<2000 {
            store.ingest(event(time: Double(index), sample: sample(0.5)))
        }
        XCTAssertEqual(store.totalEvents, 2000)
        XCTAssertEqual(store.events.count, PenStore.eventLimit)
        XCTAssertEqual(store.events.first?.timestamp, 1500)
        XCTAssertEqual(store.events.last?.id, 2000)
        XCTAssertEqual(store.selectedDevice?.history.count, PenStore.historyLimit)
    }

    func testDeviceSessionsAreBoundedAndSelectionStaysValid() {
        var store = PenStore()
        for index in 0..<100 { store.ingest(event(id: index, sample: sample(0))) }
        XCTAssertEqual(store.devices.count, PenStore.deviceLimit)
        XCTAssertNotNil(store.selectedDevice)
        XCTAssertEqual(Set(store.devices.map(\.id)).count, PenStore.deviceLimit)
    }

    func testClearResetsAllObservedData() {
        var store = PenStore()
        store.ingest(event(sample: sample(1)))
        store.clear()
        XCTAssertTrue(store.events.isEmpty)
        XCTAssertTrue(store.devices.isEmpty)
        XCTAssertNil(store.selectedIdentity)
        XCTAssertEqual(store.totalEvents, 0)
    }

    @MainActor
    func testLifecycleIsIdempotentAndLocalWorksWithoutPermission() {
        let backend = FakeBackend()
        let monitor = PenMonitor(backend: backend, accessCheck: { false })
        monitor.start()
        monitor.start()
        XCTAssertEqual(backend.starts, 1)
        XCTAssertTrue(monitor.isRunning)
        XCTAssertFalse(monitor.listenAccess)
        XCTAssertTrue(monitor.installation.local)
        XCTAssertFalse(monitor.receivedLocal)
        monitor.stop()
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
        monitor.start()
        XCTAssertEqual(backend.starts, 2)
        monitor.stop()
    }

    @MainActor
    func testFailedInstallationDoesNotReportRunning() {
        let backend = FakeBackend()
        backend.result = MonitorInstallation(local: false, global: false)
        let monitor = PenMonitor(backend: backend, accessCheck: { true })
        monitor.start()
        XCTAssertFalse(monitor.isRunning)
        XCTAssertFalse(monitor.receivedGlobal)
        monitor.stop()
    }

    @MainActor
    func testBufferedPublishingSourceStatusSelectionAndClear() throws {
        let backend = FakeBackend()
        let monitor = PenMonitor(backend: backend, accessCheck: { false })
        monitor.start()
        defer { monitor.stop() }
        let quartz = try XCTUnwrap(CGEvent(source: nil))
        quartz.type = .tabletPointer
        quartz.setIntegerValueField(.tabletEventDeviceID, value: 1)
        backend.handler?(try XCTUnwrap(NSEvent(cgEvent: quartz)), .local)
        // More than one buffer of global events must not erase the local receipt flag.
        quartz.setIntegerValueField(.tabletEventDeviceID, value: 2)
        let global = try XCTUnwrap(NSEvent(cgEvent: quartz))
        for _ in 0..<510 { backend.handler?(global, .global) }
        XCTAssertEqual(monitor.snapshot.totalEvents, 0)
        monitor.publish()
        XCTAssertEqual(monitor.snapshot.totalEvents, 511)
        XCTAssertTrue(monitor.receivedLocal)
        XCTAssertTrue(monitor.receivedGlobal)
        monitor.selectDevice(.session(2))
        XCTAssertEqual(monitor.snapshot.selectedDevice?.id, .session(2))
        let generation = monitor.clearGeneration
        monitor.clear()
        XCTAssertTrue(monitor.isRunning)
        XCTAssertEqual(monitor.snapshot.totalEvents, 0)
        XCTAssertFalse(monitor.receivedLocal)
        XCTAssertFalse(monitor.receivedGlobal)
        XCTAssertEqual(monitor.clearGeneration, generation + 1)
    }

    @MainActor
    func testRecheckingPermissionRestartsActiveMonitorsOnly() {
        let backend = FakeBackend()
        var access = false
        let monitor = PenMonitor(backend: backend, accessCheck: { access })
        monitor.start()
        access = true
        monitor.recheck()
        XCTAssertTrue(monitor.listenAccess)
        XCTAssertTrue(monitor.isRunning)
        XCTAssertEqual(backend.starts, 2)
        monitor.stop()
        monitor.recheck()
        XCTAssertFalse(monitor.isRunning)
        XCTAssertEqual(backend.starts, 2)
    }

    @MainActor
    func testOrdinaryMouseDecoderAndMonitoringIgnoreInput() {
        let backend = FakeBackend()
        let monitor = PenMonitor(backend: backend, accessCheck: { false })
        monitor.start()
        defer { monitor.stop() }
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved] {
            let mouse = NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 1,
                                          windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1,
                                          pressure: 1)!
            XCTAssertNil(PenEventDecoder.decode(mouse, source: .local, foregroundApp: "Test"))
            backend.handler?(mouse, .local)
        }
        monitor.publish()
        XCTAssertEqual(monitor.snapshot.totalEvents, 0)
        XCTAssertFalse(monitor.receivedLocal)
    }

    func testSidecarReconnectUsesOneModelIdentity() throws {
        var store = PenStore()
        let pencil = info(serial: 0, uniqueID: 0, vendor: 1452, tablet: 4762)
        store.ingest(event(id: 2105, proximity: true, info: pencil))
        let identity = try XCTUnwrap(store.selectedIdentity)
        XCTAssertEqual(identity.level, .model)
        XCTAssertEqual(identity.key, "v1:model:5ac:129a:1:pen")
        store.ingest(event(id: 2105, sample: sample(0.5)))
        store.ingest(event(id: 2105, proximity: false, info: pencil))
        store.ingest(event(id: 1858, time: 2, proximity: true, info: pencil))
        store.ingest(event(id: 1858, time: 3, sample: sample(0.6)))
        XCTAssertEqual(store.devices.count, 1)
        XCTAssertEqual(store.selectedIdentity, identity)
        XCTAssertEqual(store.selectedDevice?.lastEvent.deviceID, 1858)
        XCTAssertEqual(store.selectedDevice?.history.count, 2)
        XCTAssertEqual(store.selectedDevice?.lastSampleEvent?.sample?.pressure, 0.6)
    }

    func testUniquePenSurvivesSessionAndModelMetadataChanges() {
        var store = PenStore()
        store.ingest(event(id: 10, proximity: true, info: info()))
        let identity = store.selectedIdentity
        store.ingest(event(id: 11, proximity: true,
                           info: info(tablet: 99, capabilities: 0, systemTabletID: 42)))
        XCTAssertEqual(store.devices.count, 1)
        XCTAssertEqual(store.selectedIdentity, identity)
        XCTAssertEqual(identity?.level, .uniqueTool)
        XCTAssertEqual(identity?.key, "v1:tool:56a:a:pen")
        XCTAssertEqual(store.selectedDevice?.lastEvent.deviceID, 11)
    }

    func testDifferentPensAndToolsDoNotMerge() {
        var store = PenStore()
        store.ingest(event(id: 1, proximity: true, info: info(serial: 10)))
        store.ingest(event(id: 2, proximity: true, info: info(serial: 20)))
        store.ingest(event(id: 3, proximity: true, info: info(serial: 10, tool: "橡皮擦")))
        store.ingest(event(id: 4, proximity: true, info: info(serial: 10, vendor: 1452)))
        XCTAssertEqual(store.devices.count, 4)
    }

    func testSerialFallbackAndAllZeroMetadata() {
        let serial = PenIdentity.resolve(info: info(serial: 123, uniqueID: 0), deviceID: 1)
        let reconnected = PenIdentity.resolve(info: info(serial: 123, uniqueID: 0), deviceID: 2)
        XCTAssertEqual(serial, reconnected)
        XCTAssertEqual(serial.level, .serialNumber)
        let unknown = info(serial: 0, uniqueID: 0, vendor: 0, tablet: 0)
        XCTAssertEqual(PenIdentity.resolve(info: unknown, deviceID: 1), .session(1))
        XCTAssertNotEqual(PenIdentity.resolve(info: unknown, deviceID: 1),
                          PenIdentity.resolve(info: unknown, deviceID: 2))
    }

    func testProvisionalIdentityPromotesWithoutLosingSamplesOrSelection() {
        var store = PenStore()
        store.ingest(event(id: 77, sample: sample(0.7)))
        XCTAssertEqual(store.selectedIdentity, .session(77))
        store.ingest(event(id: 77, proximity: true, info: info()))
        XCTAssertEqual(store.devices.count, 1)
        XCTAssertEqual(store.selectedIdentity?.level, .uniqueTool)
        XCTAssertEqual(store.selectedDevice?.lastSampleEvent?.sample?.pressure, 0.7)
        XCTAssertEqual(store.selectedDevice?.history.count, 1)
    }

    func testProvisionalReconnectMergesIntoExistingStableRow() {
        var store = PenStore()
        store.ingest(event(id: 1, proximity: true, info: info()))
        store.ingest(event(id: 1, sample: sample(0.2)))
        store.ingest(event(id: 2, time: 2, sample: sample(0.8)))
        XCTAssertEqual(store.devices.count, 2)
        store.ingest(event(id: 2, time: 3, proximity: true, info: info()))
        XCTAssertEqual(store.devices.count, 1)
        XCTAssertEqual(store.selectedIdentity?.level, .uniqueTool)
        XCTAssertEqual(store.selectedDevice?.history.count, 2)
        XCTAssertEqual(store.selectedDevice?.lastSampleEvent?.sample?.pressure, 0.8)
    }

    func testOldConnectionDepartureDoesNotMarkReconnectedPenAbsent() {
        var store = PenStore()
        store.ingest(event(id: 1, proximity: true, info: info()))
        store.ingest(event(id: 2, time: 2, proximity: true, info: info()))
        store.ingest(event(id: 2, time: 3, sample: sample(0.8)))
        store.ingest(event(id: 1, time: 4, proximity: false, info: info()))
        XCTAssertEqual(store.selectedDevice?.proximity, true)
        XCTAssertEqual(store.selectedDevice?.lastEvent.deviceID, 2)
        XCTAssertEqual(store.selectedDevice?.lastSampleEvent?.sample?.pressure, 0.8)
    }

    func testAutomaticSelectionChangesOnlyWhenActivePenChanges() {
        var store = PenStore()
        store.ingest(event(id: 1, proximity: true, info: info()))
        let first = store.selectedIdentity
        store.ingest(event(id: 2, proximity: true, info: info(serial: 20)))
        let second = store.selectedIdentity
        XCTAssertNotEqual(first, second)
        store.selectedIdentity = first
        store.ingest(event(id: 2, sample: sample(0.3)))
        XCTAssertEqual(store.selectedIdentity, first, "Same active pen must respect a manual choice")
        store.ingest(event(id: 1, proximity: false, info: info()))
        XCTAssertEqual(store.selectedIdentity, first)
        store.ingest(event(id: 1, sample: sample(0.5)))
        store.selectedIdentity = second
        store.ingest(event(id: 2, sample: sample(0.6)))
        XCTAssertEqual(store.selectedIdentity, second)
        store.ingest(event(id: 1, sample: sample(0.7)))
        XCTAssertEqual(store.selectedIdentity, first)
    }

    func testAutomaticSelectionOffAndReenabling() {
        var store = PenStore()
        store.setAutomaticSwitching(false)
        store.ingest(event(id: 1, sample: sample(0)))
        store.ingest(event(id: 2, sample: sample(0)))
        XCTAssertEqual(store.selectedIdentity, .session(1))
        store.setAutomaticSwitching(true)
        XCTAssertEqual(store.selectedIdentity, .session(2))
        store.setAutomaticSwitching(false)
        store.clear()
        XCTAssertFalse(store.automaticallySwitchDevices)
        XCTAssertNil(store.lastActiveIdentity)
    }

    @MainActor
    func testAutomaticSelectionPreferencePersistsAndSurvivesClear() throws {
        let suite = "PenActorTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let monitor = PenMonitor(backend: FakeBackend(), accessCheck: { false }, preferences: preferences)
        XCTAssertTrue(monitor.automaticallySwitchDevices)
        monitor.setAutomaticSwitching(false)
        monitor.clear()
        XCTAssertFalse(monitor.automaticallySwitchDevices)
        let restored = PenMonitor(backend: FakeBackend(), accessCheck: { false }, preferences: preferences)
        XCTAssertFalse(restored.automaticallySwitchDevices)
        restored.setAutomaticSwitching(true)
        XCTAssertEqual(preferences.object(forKey: PenMonitor.automaticSwitchingPreference) as? Bool, true)
    }

    @MainActor
    func testPlainMouseUpEndsActiveTabletGesture() throws {
        let recognizer = TrackingPenRecognizer(target: nil, action: nil)
        let view = NSView()
        view.addGestureRecognizer(recognizer)
        recognizer.mouseDown(with: try gestureEvent(type: .leftMouseDown, subtype: 1, pressure: 0.5))
        XCTAssertTrue(recognizer.hasActiveStroke)
        // Sidecar can end a tablet mouse sequence with an ordinary mouse release.
        recognizer.mouseUp(with: try gestureEvent(type: .leftMouseUp, subtype: 0, pressure: 0))
        XCTAssertFalse(recognizer.hasActiveStroke)
        XCTAssertEqual(recognizer.state, .ended)
    }

    @MainActor
    func testTabletZeroPressureAndExplicitCancellationEndGestures() throws {
        let recognizer = TrackingPenRecognizer(target: nil, action: nil)
        let view = NSView()
        view.addGestureRecognizer(recognizer)
        recognizer.tabletPoint(with: try gestureEvent(type: .tabletPointer, pressure: 0.5))
        XCTAssertTrue(recognizer.hasActiveStroke)
        recognizer.tabletPoint(with: try gestureEvent(type: .tabletPointer, pressure: 0))
        XCTAssertFalse(recognizer.hasActiveStroke)
        recognizer.reset()
        recognizer.state = .possible
        recognizer.mouseDown(with: try gestureEvent(type: .leftMouseDown, subtype: 1, pressure: 0.5))
        XCTAssertTrue(recognizer.hasActiveStroke)
        recognizer.cancelOutstandingStroke()
        XCTAssertFalse(recognizer.hasActiveStroke)
    }

    @MainActor
    func testOrdinaryMouseCannotBeginTestPadGesture() throws {
        let recognizer = TrackingPenRecognizer(target: nil, action: nil)
        let plain = try gestureEvent(type: .leftMouseDown, subtype: 0, pressure: 1)
        XCTAssertFalse(recognizer.gestureRecognizer(recognizer, shouldAttemptToRecognizeWith: plain))
        recognizer.mouseDown(with: plain)
        XCTAssertFalse(recognizer.hasActiveStroke)
    }

    @MainActor
    func testTestPadDoesNotExclusivelyLockOtherControls() {
        let view = PenTestView()
        defer { view.tearDown() }
        if #available(macOS 27.0, *) {
            XCTAssertEqual(view.exclusiveGestureBehavior, .notExclusive)
        }
    }

    func testPencilDoubleTapPairsAppKitAndSwiftUIOnce() {
        var stats = PencilInteractionStats()
        let date = Date(timeIntervalSince1970: 123)
        stats.doubleTap(source: .appKit, uptime: 1, date: date)
        stats.doubleTap(source: .swiftUI, uptime: 1.02, date: date)
        XCTAssertEqual(stats.doubleTapCount, 1)
        XCTAssertTrue(stats.doubleTapPaired)
        XCTAssertEqual(stats.lastDoubleTapAt, date)
        stats.doubleTap(source: .swiftUI, uptime: 2, date: date)
        stats.doubleTap(source: .appKit, uptime: 2.01, date: date)
        XCTAssertEqual(stats.doubleTapCount, 2)
        XCTAssertTrue(stats.doubleTapPaired)
    }

    func testPencilDoubleTapDoesNotDebounceDistinctOrSameSourceEvents() {
        var stats = PencilInteractionStats()
        let date = Date()
        stats.doubleTap(source: .appKit, uptime: 1, date: date)
        stats.doubleTap(source: .appKit, uptime: 1.05, date: date)
        XCTAssertEqual(stats.doubleTapCount, 2)
        stats.doubleTap(source: .swiftUI, uptime: 2, date: date)
        XCTAssertEqual(stats.doubleTapCount, 3)
        XCTAssertFalse(stats.doubleTapPaired)
    }

    func testPencilSqueezeCountsGestureInsteadOfActiveCallbacks() {
        var stats = PencilInteractionStats()
        let date = Date()
        for _ in 0..<100 { stats.squeeze(.active, date: date) }
        XCTAssertEqual(stats.squeezeCount, 1)
        XCTAssertEqual(stats.squeezeStatus, .active)
        stats.squeeze(.ended, date: date)
        XCTAssertEqual(stats.squeezeCount, 1)
        XCTAssertEqual(stats.squeezeCompletedCount, 1)
        XCTAssertEqual(stats.squeezeStatus, .ended)
        XCTAssertEqual(stats.lastSqueezeAt, date)
        stats.squeeze(.active, date: date)
        stats.squeeze(.failed, date: date)
        XCTAssertEqual(stats.squeezeCount, 2)
        XCTAssertEqual(stats.squeezeFailedCount, 1)
    }

    func testPencilSqueezeTerminalOnlyAndInterruptedCallbacks() {
        var stats = PencilInteractionStats()
        let date = Date()
        stats.squeeze(.ended, date: date)
        XCTAssertEqual(stats.squeezeCount, 1)
        XCTAssertEqual(stats.squeezeCompletedCount, 1)
        stats.squeeze(.active, date: date)
        stats.interrupt(date: date)
        XCTAssertEqual(stats.squeezeStatus, .interrupted)
        stats.squeeze(.ended, date: date)
        XCTAssertEqual(stats.squeezeCount, 2)
        XCTAssertEqual(stats.squeezeCompletedCount, 1)
        stats.squeeze(.active, date: date)
        XCTAssertEqual(stats.squeezeCount, 3)
    }

    @MainActor
    func testPencilInteractionMonitoringRespectsStopAndClear() {
        let monitor = PenMonitor(backend: FakeBackend(), accessCheck: { false })
        monitor.recordPencilDoubleTap(source: .swiftUI)
        monitor.recordPencilSqueeze(.active)
        monitor.publish()
        XCTAssertEqual(monitor.pencilInteractions.doubleTapCount, 0)
        XCTAssertEqual(monitor.pencilInteractions.squeezeCount, 0)
        monitor.start()
        monitor.recordPencilDoubleTap(source: .appKit)
        monitor.recordPencilSqueeze(.active)
        monitor.publish()
        XCTAssertEqual(monitor.pencilInteractions.doubleTapCount, 1)
        XCTAssertEqual(monitor.pencilInteractions.squeezeCount, 1)
        XCTAssertTrue(monitor.snapshot.devices.isEmpty, "Gesture callbacks must not invent a hardware identity")
        monitor.stop()
        XCTAssertEqual(monitor.pencilInteractions.squeezeStatus, .interrupted)
        monitor.recordPencilDoubleTap(source: .appKit)
        monitor.recordPencilSqueeze(.ended)
        monitor.publish()
        XCTAssertEqual(monitor.pencilInteractions.doubleTapCount, 1)
        XCTAssertEqual(monitor.pencilInteractions.squeezeCompletedCount, 0)
        monitor.clear()
        XCTAssertEqual(monitor.pencilInteractions.doubleTapCount, 0)
        XCTAssertNil(monitor.pencilInteractions.lastDoubleTapAt)
        XCTAssertEqual(monitor.pencilInteractions.squeezeStatus, .waiting)
        XCTAssertEqual(monitor.pencilInteractions.squeezeCount, 0)
    }

    func testPencilInterruptionResetsCrossSourcePairing() {
        var stats = PencilInteractionStats()
        let date = Date()
        stats.doubleTap(source: .appKit, uptime: 1, date: date)
        stats.interrupt(date: date)
        stats.doubleTap(source: .swiftUI, uptime: 1.01, date: date)
        XCTAssertEqual(stats.doubleTapCount, 2)
    }

    private func gestureEvent(type: CGEventType, subtype: Int64 = 0, pressure: Double) throws -> NSEvent {
        let quartz = try XCTUnwrap(CGEvent(source: nil))
        quartz.type = type
        quartz.setIntegerValueField(.mouseEventSubtype, value: subtype)
        quartz.setDoubleValueField(.tabletEventPointPressure, value: pressure)
        quartz.setDoubleValueField(.mouseEventPressure, value: pressure)
        return try XCTUnwrap(NSEvent(cgEvent: quartz))
    }

    private func event(id: Int = 1, time: Double = 1, proximity: Bool? = nil,
                       info: PenDeviceInfo? = nil, sample: PenSample? = nil) -> PenEvent {
        PenEvent(deviceID: id, timestamp: time, receivedAt: Date(timeIntervalSince1970: time),
                 source: .local, typeName: proximity == nil ? "tabletPoint" : "tabletProximity",
                 foregroundApp: "Test", proximity: proximity, info: info, sample: sample)
    }

    private func sample(_ pressure: Float?) -> PenSample {
        PenSample(pressure: pressure, tiltX: 0, tiltY: 0, rotation: 0, tangentialPressure: 0,
                  absoluteX: 100, absoluteY: 200, absoluteZ: 0, buttons: pressure == 0 ? 0 : 1)
    }

    private func info(serial: Int = 10, uniqueID: UInt64? = nil, vendor: Int = 1386,
                      tablet: Int = 1, tool: String = "笔", capabilities: Int = 0x05C7,
                      systemTabletID: Int = 1) -> PenDeviceInfo {
        PenDeviceInfo(vendorID: vendor, tabletID: tablet, pointingDeviceID: 0, systemTabletID: systemTabletID,
                      vendorPointingDeviceType: 1, serialNumber: serial, uniqueID: uniqueID ?? UInt64(serial),
                      capabilityMask: capabilities, toolType: tool)
    }
}

@MainActor
private final class TrackingPenRecognizer: PenStrokeRecognizer {
    // AppKit owns state outside an actual gathered gesture sequence. Provide the
    // tracking state here so fixtures test our handlers without posting OS input.
    private var trackingState: NSGestureRecognizer.State = .possible
    override var state: NSGestureRecognizer.State {
        get { trackingState }
        set { trackingState = newValue }
    }
}

@MainActor
private final class FakeBackend: EventMonitoring {
    var starts = 0
    var result = MonitorInstallation(local: true, global: true)
    var handler: (@MainActor (NSEvent, EventSource) -> Void)?
    func start(handler: @escaping @MainActor (NSEvent, EventSource) -> Void) -> MonitorInstallation {
        starts += 1
        self.handler = handler
        return result
    }
    func stop() { handler = nil }
}
