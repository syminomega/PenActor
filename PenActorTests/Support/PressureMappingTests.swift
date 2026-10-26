import XCTest
import AppKit
import SwiftUI
@testable import PenActor

/// Shared fixtures; tests are grouped by responsibility in adjacent directories.
final class PressureMappingTests: XCTestCase {
    let identity = PenIdentity(key: "v1:model:5ac:129a:0:pen", level: .model)
    func profile(curve: PressureCurve = .light) -> PressureProfile {
        PressureProfile(name: "Pencil", device: identity, curve: curve, targetBundleIDs: ["com.adobe.Photoshop"])
    }

    func proximity(id: Int64 = 17, entering: Bool = true, vendor: Int64 = 1452, type: CGEventType = .tabletProximity) throws -> CGEvent {
        let e = try XCTUnwrap(CGEvent(source: nil)); e.type = type
        if type != .tabletProximity { e.setIntegerValueField(.mouseEventSubtype, value: 2) }
        for (field, value): (CGEventField, Int64) in [(.tabletProximityEventDeviceID, id), (.tabletProximityEventVendorID, vendor),
            (.tabletProximityEventTabletID, 4762), (.tabletProximityEventPointerType, 1), (.tabletProximityEventEnterProximity, entering ? 1 : 0)] {
            e.setIntegerValueField(field, value: value)
        }
        return e
    }

    func point(_ p: Double, id: Int64 = 17, pid: Int64 = 42, type: CGEventType = .tabletPointer, pen: Bool = true) throws -> CGEvent {
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

    func processor(_ p: PressureProfile? = nil) -> PressureMappingProcessor {
        var m = PressureMappingProcessor(); m.setProfiles([p ?? profile()]); m.applications = [42: "com.adobe.Photoshop", 43: "other.app"]
        return m
    }

    func deviceProfile(_ device: PenIdentity? = nil) -> PressureProfile {
        PressureProfile(name: "绘画", device: device ?? identity, applicationRules: [
            ApplicationPressureRule(bundleID: "com.adobe.Photoshop", name: "Photoshop"),
            ApplicationPressureRule(bundleID: "other.app", name: "CSP fixture")
        ])
    }

    func shape(_ state: inout StrokeTaperState, settings: StrokeTaperSettings, pressure: Double = 0.5,
                       time: Double, x: Double = 0, ending: Bool = false)
        -> (pressure: Double, tabletPressure: Double, diagnostic: StrokeTaperDiagnostic) {
        state.apply(settings: settings, input: pressure, tabletInput: pressure, curvePressure: pressure,
                    tabletCurvePressure: pressure, timestamp: time, location: CGPoint(x: x, y: 0), isEnding: ending)
    }

    func bufferedProfile() -> PressureProfile {
        var p = profile(); p.taper.exitEnabled = true; return p
    }

    func queue(_ event: CGEvent, processor: inout PressureMappingProcessor, buffer: inout BufferedPenEvents,
                       now: Double) throws -> PenBufferAction {
        let original = try XCTUnwrap(event.copy())
        let result = processor.process(event, recordDiagnostic: false)
        return buffer.accept(event, original: original, result: result, now: now)
    }

    func timedPoint(_ p: Double, time: Double, type: CGEventType = .leftMouseDragged, id: Int64 = 17,
                            pid: Int64 = 42, pen: Bool = true) throws -> CGEvent {
        let e = try point(p, id: id, pid: pid, type: type, pen: pen)
        e.timestamp = UInt64((time*1_000_000_000).rounded()); return e
    }
}
