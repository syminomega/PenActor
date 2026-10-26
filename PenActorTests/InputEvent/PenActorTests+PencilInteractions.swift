import XCTest
import AppKit
import SwiftUI
@testable import PenActor

extension PenActorTests {
    func testPencilDoubleTapPairsAppKitAndSwiftUIOnce() {
        var stats = PencilInteractionStats()
        let date = Date(timeIntervalSince1970: 123)
        stats.doubleTap(source: .appKit, uptime: 1, date: date)
        stats.doubleTap(source: .swiftUI, uptime: 1.02, date: date)
        XCTAssertEqual(stats.doubleTapCount, 1)
        XCTAssertTrue(stats.doubleTapPaired)
        XCTAssertEqual(stats.lastDoubleTapAt, date)
        stats.doubleTap(source: .swiftUI, uptime: 2, date: date)
        stats.doubleTap(source: .appKit, uptime: 2.01, date: date)
        XCTAssertEqual(stats.doubleTapCount, 2)
        XCTAssertTrue(stats.doubleTapPaired)
    }

    func testPencilDoubleTapDoesNotDebounceDistinctOrSameSourceEvents() {
        var stats = PencilInteractionStats()
        let date = Date()
        stats.doubleTap(source: .appKit, uptime: 1, date: date)
        stats.doubleTap(source: .appKit, uptime: 1.05, date: date)
        XCTAssertEqual(stats.doubleTapCount, 2)
        stats.doubleTap(source: .swiftUI, uptime: 2, date: date)
        XCTAssertEqual(stats.doubleTapCount, 3)
        XCTAssertFalse(stats.doubleTapPaired)
    }

    func testPencilSqueezeCountsGestureInsteadOfActiveCallbacks() {
        var stats = PencilInteractionStats()
        let date = Date()
        for _ in 0..<100 { stats.squeeze(.active, date: date) }
        XCTAssertEqual(stats.squeezeCount, 1)
        XCTAssertEqual(stats.squeezeStatus, .active)
        stats.squeeze(.ended, date: date)
        XCTAssertEqual(stats.squeezeCount, 1)
        XCTAssertEqual(stats.squeezeCompletedCount, 1)
        XCTAssertEqual(stats.squeezeStatus, .ended)
        XCTAssertEqual(stats.lastSqueezeAt, date)
        stats.squeeze(.active, date: date)
        stats.squeeze(.failed, date: date)
        XCTAssertEqual(stats.squeezeCount, 2)
        XCTAssertEqual(stats.squeezeFailedCount, 1)
    }

    func testPencilSqueezeTerminalOnlyAndInterruptedCallbacks() {
        var stats = PencilInteractionStats()
        let date = Date()
        stats.squeeze(.ended, date: date)
        XCTAssertEqual(stats.squeezeCount, 1)
        XCTAssertEqual(stats.squeezeCompletedCount, 1)
        stats.squeeze(.active, date: date)
        stats.interrupt(date: date)
        XCTAssertEqual(stats.squeezeStatus, .interrupted)
        stats.squeeze(.ended, date: date)
        XCTAssertEqual(stats.squeezeCount, 2)
        XCTAssertEqual(stats.squeezeCompletedCount, 1)
        stats.squeeze(.active, date: date)
        XCTAssertEqual(stats.squeezeCount, 3)
    }

    @MainActor
    func testPencilInteractionMonitoringRespectsStopAndClear() {
        let monitor = PenMonitor(backend: FakeBackend(), accessCheck: { false })
        monitor.recordPencilDoubleTap(source: .swiftUI)
        monitor.recordPencilSqueeze(.active)
        monitor.publish()
        XCTAssertEqual(monitor.pencilInteractions.doubleTapCount, 0)
        XCTAssertEqual(monitor.pencilInteractions.squeezeCount, 0)
        monitor.start()
        monitor.recordPencilDoubleTap(source: .appKit)
        monitor.recordPencilSqueeze(.active)
        monitor.publish()
        XCTAssertEqual(monitor.pencilInteractions.doubleTapCount, 1)
        XCTAssertEqual(monitor.pencilInteractions.squeezeCount, 1)
        XCTAssertTrue(monitor.snapshot.devices.isEmpty, "Gesture callbacks must not invent a hardware identity")
        monitor.stop()
        XCTAssertEqual(monitor.pencilInteractions.squeezeStatus, .interrupted)
        monitor.recordPencilDoubleTap(source: .appKit)
        monitor.recordPencilSqueeze(.ended)
        monitor.publish()
        XCTAssertEqual(monitor.pencilInteractions.doubleTapCount, 1)
        XCTAssertEqual(monitor.pencilInteractions.squeezeCompletedCount, 0)
        monitor.clear()
        XCTAssertEqual(monitor.pencilInteractions.doubleTapCount, 0)
        XCTAssertNil(monitor.pencilInteractions.lastDoubleTapAt)
        XCTAssertEqual(monitor.pencilInteractions.squeezeStatus, .waiting)
        XCTAssertEqual(monitor.pencilInteractions.squeezeCount, 0)
    }

    func testPencilInterruptionResetsCrossSourcePairing() {
        var stats = PencilInteractionStats()
        let date = Date()
        stats.doubleTap(source: .appKit, uptime: 1, date: date)
        stats.interrupt(date: date)
        stats.doubleTap(source: .swiftUI, uptime: 1.01, date: date)
        XCTAssertEqual(stats.doubleTapCount, 2)
    }
}
