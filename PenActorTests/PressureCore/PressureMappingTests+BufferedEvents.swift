import XCTest
import AppKit
import SwiftUI
@testable import PenActor

extension PressureMappingTests {
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
}
