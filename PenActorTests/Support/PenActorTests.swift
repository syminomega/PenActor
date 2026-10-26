import XCTest
import AppKit
import SwiftUI
@testable import PenActor

/// Shared fixtures; tests are grouped by responsibility in adjacent directories.
final class PenActorTests: XCTestCase {
    func gestureEvent(type: CGEventType, subtype: Int64 = 0, pressure: Double) throws -> NSEvent {
        let quartz = try XCTUnwrap(CGEvent(source: nil))
        quartz.type = type
        quartz.setIntegerValueField(.mouseEventSubtype, value: subtype)
        quartz.setDoubleValueField(.tabletEventPointPressure, value: pressure)
        quartz.setDoubleValueField(.mouseEventPressure, value: pressure)
        return try XCTUnwrap(NSEvent(cgEvent: quartz))
    }

    func event(id: Int = 1, time: Double = 1, proximity: Bool? = nil,
                       info: PenDeviceInfo? = nil, sample: PenSample? = nil) -> PenEvent {
        PenEvent(deviceID: id, timestamp: time, receivedAt: Date(timeIntervalSince1970: time),
                 source: .local, typeName: proximity == nil ? "tabletPoint" : "tabletProximity",
                 foregroundApp: "Test", proximity: proximity, info: info, sample: sample)
    }

    func sample(_ pressure: Float?) -> PenSample {
        PenSample(pressure: pressure, tiltX: 0, tiltY: 0, rotation: 0, tangentialPressure: 0,
                  absoluteX: 100, absoluteY: 200, absoluteZ: 0, buttons: pressure == 0 ? 0 : 1)
    }

    func info(serial: Int = 10, uniqueID: UInt64? = nil, vendor: Int = 1386,
                      tablet: Int = 1, tool: String = "笔", capabilities: Int = 0x05C7,
                      systemTabletID: Int = 1) -> PenDeviceInfo {
        PenDeviceInfo(vendorID: vendor, tabletID: tablet, pointingDeviceID: 0, systemTabletID: systemTabletID,
                      vendorPointingDeviceType: 1, serialNumber: serial, uniqueID: uniqueID ?? UInt64(serial),
                      capabilityMask: capabilities, toolType: tool)
    }
}
