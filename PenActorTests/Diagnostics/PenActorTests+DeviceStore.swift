import XCTest
import AppKit
import SwiftUI
@testable import PenActor

extension PenActorTests {
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
        XCTAssertEqual(store.selectedDevice?.status, String(localized: "Out of range · Showing previous readings"))
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
        XCTAssertEqual(PenCapability.rotation.support(mask: nil), String(localized: "Support unknown"))
        XCTAssertEqual(PenCapability.rotation.support(mask: 0), String(localized: "Support unknown"))
        XCTAssertEqual(PenCapability.rotation.support(mask: 0x0400), String(localized: "Not declared by driver"))
        XCTAssertEqual(PenCapability.rotation.support(mask: 0x2000), String(localized: "Declared by driver"))
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
}
