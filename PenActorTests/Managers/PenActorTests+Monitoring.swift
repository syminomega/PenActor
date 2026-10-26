import XCTest
import AppKit
import SwiftUI
@testable import PenActor

extension PenActorTests {
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
}
