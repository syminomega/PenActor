import XCTest
import AppKit
import SwiftUI
@testable import PenActor

extension PenActorTests {
    @MainActor
    func testTabletZeroPressureAndExplicitCancellationEndGestures() throws {
        let recognizer = TrackingPenRecognizer(target: nil, action: nil)
        let view = NSView()
        view.addGestureRecognizer(recognizer)
        recognizer.tabletPoint(with: try gestureEvent(type: .tabletPointer, pressure: 0.5))
        XCTAssertTrue(recognizer.hasActiveStroke)
        recognizer.tabletPoint(with: try gestureEvent(type: .tabletPointer, pressure: 0))
        XCTAssertFalse(recognizer.hasActiveStroke)
        recognizer.reset()
        recognizer.state = .possible
        recognizer.mouseDown(with: try gestureEvent(type: .leftMouseDown, subtype: 1, pressure: 0.5))
        XCTAssertTrue(recognizer.hasActiveStroke)
        recognizer.cancelOutstandingStroke()
        XCTAssertFalse(recognizer.hasActiveStroke)
    }

    @MainActor
    func testOrdinaryMouseCannotBeginTestPadGesture() throws {
        let recognizer = TrackingPenRecognizer(target: nil, action: nil)
        let plain = try gestureEvent(type: .leftMouseDown, subtype: 0, pressure: 1)
        XCTAssertFalse(recognizer.gestureRecognizer(recognizer, shouldAttemptToRecognizeWith: plain))
        recognizer.mouseDown(with: plain)
        XCTAssertFalse(recognizer.hasActiveStroke)
    }

    @MainActor
    func testTestPadDoesNotExclusivelyLockOtherControls() {
        let view = PenTestView()
        defer { view.tearDown() }
        if #available(macOS 27.0, *) {
            XCTAssertEqual(view.exclusiveGestureBehavior, .notExclusive)
        }
    }
}
