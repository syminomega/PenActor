import XCTest
import AppKit
import SwiftUI
@testable import PenActor

@MainActor
final class TrackingPenRecognizer: PenStrokeRecognizer {
    // AppKit owns state outside an actual gathered gesture sequence. Provide the
    // tracking state here so fixtures test our handlers without posting OS input.
    private var trackingState: NSGestureRecognizer.State = .possible
    override var state: NSGestureRecognizer.State {
        get { trackingState }
        set { trackingState = newValue }
    }
}

@MainActor
final class FakeBackend: EventMonitoring {
    var starts = 0
    var result = MonitorInstallation(local: true, global: true)
    var handler: (@MainActor (NSEvent, EventSource) -> Void)?
    func start(handler: @escaping @MainActor (NSEvent, EventSource) -> Void) -> MonitorInstallation {
        starts += 1
        self.handler = handler
        return result
    }
    func stop() { handler = nil }
}
