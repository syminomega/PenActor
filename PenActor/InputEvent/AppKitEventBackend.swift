import AppKit

/// AppKit observation is independent of the active Quartz remapping tap.
struct MonitorInstallation {
    let local: Bool
    let global: Bool
}

@MainActor
protocol EventMonitoring: AnyObject {
    func start(handler: @escaping @MainActor (NSEvent, EventSource) -> Void) -> MonitorInstallation
    func stop()
}

@MainActor
final class AppKitEventBackend: EventMonitoring {
    private var localToken: Any?
    private var globalToken: Any?

    func start(handler: @escaping @MainActor (NSEvent, EventSource) -> Void) -> MonitorInstallation {
        stop()
        let mask: NSEvent.EventTypeMask = [
            .tabletPoint, .tabletProximity, .mouseMoved,
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged
        ]
        // AppKit documents both monitor callbacks as main-thread callbacks.
        localToken = NSEvent.addLocalMonitorForEvents(matching: mask.union(.changeMode)) { event in
            MainActor.assumeIsolated { handler(event, .local) }
            return event
        }
        globalToken = NSEvent.addGlobalMonitorForEvents(matching: mask) { event in
            MainActor.assumeIsolated { handler(event, .global) }
        }
        return MonitorInstallation(local: localToken != nil, global: globalToken != nil)
    }

    func stop() {
        if let localToken { NSEvent.removeMonitor(localToken) }
        if let globalToken { NSEvent.removeMonitor(globalToken) }
        localToken = nil
        globalToken = nil
    }
}
