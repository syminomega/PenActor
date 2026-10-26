import XCTest
import AppKit
import SwiftUI
@testable import PenActor

extension PressureMappingTests {
    func testInvalidTaperSettingsAreRejected() {
        var p = profile()
        p.taper.entryDistance = 0; XCTAssertFalse(p.isValid)
        p.taper = StrokeTaperSettings(); p.taper.entryDurationMS = .nan; XCTAssertFalse(p.isValid)
        p.taper = StrokeTaperSettings(); p.taper.exitDurationMS = 1; XCTAssertFalse(p.isValid)
        p.taper = StrokeTaperSettings(); p.taper.exitDurationMS = .infinity; XCTAssertFalse(p.isValid)
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
}
