import XCTest
import AppKit
import SwiftUI
@testable import PenActor

extension PenActorTests {
    func testJSONExportPreservesPrecisionZeroMissingAndDeviceIdentity() throws {
        var store = PenStore()
        store.ingest(event(time: 100.000123, proximity: true, info: info()))
        store.ingest(event(time: 100.008456, sample: sample(20.0 / 255.0)))
        store.ingest(event(time: 100.016789, sample: sample(0)))
        store.ingest(event(time: 100.025123, sample: sample(nil)))
        let date = Date(timeIntervalSince1970: 1_792_580_000.123)
        let log = PenLogDocument(store: store, interactions: PencilInteractionStats(), isMonitoring: false,
                                 exportedAt: date)
        let data = try log.jsonData()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let events = try XCTUnwrap(object["events"] as? [[String: Any]])
        let samples = try events.dropFirst().map { try XCTUnwrap($0["sample"] as? [String: Any]) }
        XCTAssertEqual(try XCTUnwrap(samples[0]["pressure"] as? Double), Double(Float(20.0 / 255.0)), accuracy: 0.00000001)
        XCTAssertEqual(samples[1]["pressure"] as? Double, 0)
        XCTAssertTrue(samples[2]["pressure"] is NSNull)
        XCTAssertEqual(events[1]["timestamp"] as? Double, 100.008456)
        XCTAssertEqual((events[1]["identityAtCapture"] as? [String: Any])?["key"] as? String, "v1:tool:56a:a:pen")
        let exportedAt = try XCTUnwrap(object["exportedAt"] as? String)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertTrue(exportedAt.contains(".") && exportedAt.hasSuffix("Z"))
        XCTAssertEqual(try XCTUnwrap(formatter.date(from: exportedAt)).timeIntervalSince1970,
                       date.timeIntervalSince1970, accuracy: 0.0011)
        XCTAssertEqual(object["schemaVersion"] as? Int, 4)
        XCTAssertEqual(object["retainedEventCount"] as? Int, 4)
        XCTAssertEqual(object["discardedEventCount"] as? Int, 0)
    }

    func testJSONExportContainsOnlyRetainedEventsInCaptureOrder() throws {
        var store = PenStore()
        for i in 0..<550 { store.ingest(event(id: i % 2, time: Double(i), sample: sample(0.5))) }
        let log = PenLogDocument(store: store, interactions: PencilInteractionStats(), isMonitoring: true)
        XCTAssertEqual(log.events.count, 500)
        XCTAssertEqual(log.totalObservedEvents, 550)
        XCTAssertEqual(log.discardedEventCount, 50)
        XCTAssertEqual(log.events.first?.id, 51)
        XCTAssertEqual(log.events.last?.id, 550)
        XCTAssertEqual(Set(log.events.map(\.deviceID)), [0, 1])
        // Save + decode the actual JSON format in a temporary folder.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PenActorTests-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try log.jsonData().write(to: url, options: .atomic)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return try XCTUnwrap(formatter.date(from: text))
        }
        let decoded = try decoder.decode(PenLogDocument.self, from: Data(contentsOf: url))
        XCTAssertEqual(decoded.events.map(\.id), log.events.map(\.id))
        XCTAssertEqual(decoded.events.first?.sample, log.events.first?.sample)
    }

    @MainActor
    func testExportSnapshotIncludesUnpublishedEventsAndRemainsImmutable() throws {
        let backend = FakeBackend()
        let monitor = PenMonitor(backend: backend, accessCheck: { false })
        monitor.start()
        defer { monitor.stop() }
        let quartz = try XCTUnwrap(CGEvent(source: nil))
        quartz.type = .tabletPointer
        quartz.setIntegerValueField(.tabletEventDeviceID, value: 17)
        backend.handler?(try XCTUnwrap(NSEvent(cgEvent: quartz)), .global)
        XCTAssertEqual(monitor.snapshot.totalEvents, 0)
        let exported = monitor.makeLogDocument()
        XCTAssertEqual(exported.events.count, 1)
        XCTAssertEqual(exported.events[0].eventTypeCode, NSEvent.EventType.tabletPoint.rawValue)
        XCTAssertEqual(exported.events[0].identityAtCapture, .session(17))
        XCTAssertNotNil(exported.events[0].screenX)
        monitor.clear()
        XCTAssertEqual(monitor.makeLogDocument().events.count, 0)
        XCTAssertEqual(exported.events.count, 1)
    }

    func testEmptyExportIsValidAndIncludesGestureSummary() throws {
        var gestures = PencilInteractionStats()
        gestures.doubleTap(source: .appKit, uptime: 1, date: Date())
        gestures.squeeze(.active, date: Date())
        gestures.squeeze(.ended, date: Date())
        let log = PenLogDocument(store: PenStore(), interactions: gestures, isMonitoring: false)
        XCTAssertNoThrow(try log.jsonData())
        XCTAssertEqual(log.retainedEventCount, 0)
        XCTAssertEqual(log.pencilGestures.doubleTapCount, 1)
        XCTAssertEqual(log.pencilGestures.squeezeCompletedCount, 1)
    }
}
