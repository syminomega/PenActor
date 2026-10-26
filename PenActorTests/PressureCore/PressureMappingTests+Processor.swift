import XCTest
import AppKit
import SwiftUI
@testable import PenActor

extension PressureMappingTests {
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

    func testExportContainsIndependentMappingSnapshot() throws {
        var m = processor(); m.process(try proximity()); m.process(try point(0.5))
        let document = PenLogDocument(store:PenStore(),interactions:PencilInteractionStats(),isMonitoring:true,profiles:[profile()],mapping:m.snapshot)
        let data = try document.jsonData()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertEqual(object["schemaVersion"] as? Int,4)
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

    func testPressureProcessingNeverChangesPointerCoordinatesOrMousePayload() throws {
        var m = processor();m.process(try proximity())
        let fields: [CGEventField] = [.mouseEventDeltaX,.mouseEventDeltaY,.tabletEventPointX,.tabletEventPointY,
            .tabletEventPointButtons,.mouseEventNumber,.mouseEventClickState,.tabletEventDeviceID,.mouseEventSubtype]
        for type: CGEventType in [.leftMouseDown,.leftMouseDragged,.leftMouseUp] {
            let e = try point(type == .leftMouseUp ? 0 : 0.5,type:type)
            e.location = .init(x:-1091,y:367.5625)
            e.setIntegerValueField(.tabletEventPointX,value:-1091)
            e.setIntegerValueField(.tabletEventPointY,value:367)
            e.setIntegerValueField(.mouseEventDeltaY,value:-3)
            let location = e.location, values = fields.map { e.getIntegerValueField($0) }
            m.process(e)
            XCTAssertEqual(e.location,location);XCTAssertEqual(fields.map { e.getIntegerValueField($0) },values)
            XCTAssertEqual(e.getDoubleValueField(.tabletEventPointPressure),type == .leftMouseUp ? 0 : 0.8,accuracy:0.005)
        }
        for type: CGEventType in [.rightMouseDown,.rightMouseDragged,.rightMouseUp] {
            let mouse = try point(0.5,type:type,pen:false)
            let original = mouse.data
            XCTAssertNil(m.process(mouse));XCTAssertEqual(mouse.data,original)
        }
    }
}
