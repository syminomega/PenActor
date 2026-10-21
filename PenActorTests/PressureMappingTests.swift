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
        var m = PressureMappingProcessor(); m.setProfiles([p ?? profile()]); m.applications = [42: "com.adobe.Photoshop", 43: "other.app"]
        return m
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
        XCTAssertEqual(object["schemaVersion"] as? Int,2)
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

    func testLegacyProfilesLoadWithTaperDisabledAndSaveAsVersionTwo() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repo = PressureProfileRepository(url: root.appending(path: "profiles.json"))
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile())) as? [String: Any])
        old.removeValue(forKey: "taper")
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "profiles": [old]]).write(to: repo.url)
        let loaded = try repo.load()
        XCTAssertEqual(loaded.first?.taper, StrokeTaperSettings())
        try repo.save(loaded)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: repo.url)) as? [String: Any])
        XCTAssertEqual(saved["schemaVersion"] as? Int, 2)
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
        e.timestamp = UInt64(time*1_000_000_000); return e
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
        let host = NSHostingView(rootView: PressureMappingPanel(monitor: monitor, initialProfile: p).padding().frame(width: 1000, height: 860))
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
    let event: NSEvent
    init(event: NSEvent) { self.event = event }
    func start(handler: @escaping @MainActor (NSEvent, EventSource) -> Void) -> MonitorInstallation {
        handler(event, .local)
        return MonitorInstallation(local: true, global: false)
    }
    func stop() { }
}
