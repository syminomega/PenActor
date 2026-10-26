import XCTest
import AppKit
import SwiftUI
@testable import PenActor

@MainActor final class MappingPanelBackend: EventMonitoring {
    let events: [NSEvent]
    init(event: NSEvent) { events = [event] }
    init(events: [NSEvent]) { self.events = events }
    func start(handler: @escaping @MainActor (NSEvent, EventSource) -> Void) -> MonitorInstallation {
        for event in events { handler(event, .local) }
        return MonitorInstallation(local: true, global: false)
    }
    func stop() { }
}
