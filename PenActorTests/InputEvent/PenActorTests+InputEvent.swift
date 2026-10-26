import XCTest
import AppKit
import SwiftUI
@testable import PenActor

extension PenActorTests {
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
}
