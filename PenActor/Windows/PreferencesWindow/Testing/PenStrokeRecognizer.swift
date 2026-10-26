import AppKit

/// Recognizes strokes only inside the test pad; cancellation ends contact without a tracking loop.
class PenStrokeRecognizer: NSGestureRecognizer, NSGestureRecognizerDelegate {
    private(set) var penEvent: NSEvent?

    var hasActiveStroke: Bool { state == .began || state == .changed }

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func accept(_ event: NSEvent, ending: Bool = false) {
        // A release may be an ordinary mouseUp, without the tablet subtype.
        // End an existing stroke before filtering the initiating event type.
        if ending && hasActiveStroke {
            penEvent = event
            state = .ended
            return
        }
        guard TabletEventKind.classify(event) == .point else {
            if state == .possible { state = .failed }
            return
        }
        penEvent = event
        if ending {
            if state == .began || state == .changed { state = .ended }
            else { state = .failed }
        } else if state == .possible {
            state = .began
        } else if state == .began || state == .changed {
            state = .changed
        }
    }

    override func mouseDown(with event: NSEvent) { accept(event) }
    override func mouseDragged(with event: NSEvent) { accept(event) }
    override func mouseUp(with event: NSEvent) { accept(event, ending: true) }
    override func tabletPoint(with event: NSEvent) {
        guard event.type == .tabletPoint else { return }
        let touching = event.pressure > 0
        if touching { accept(event) }
        else if state == .began || state == .changed { accept(event, ending: true) }
    }

    @available(macOS 26.0, *)
    override func mouseCancelled(with event: NSEvent) { cancel() }
    override func touchesCancelled(with event: NSEvent) { cancel() }

    private func cancel() {
        state = (state == .began || state == .changed) ? .cancelled : .failed
    }

    func cancelOutstandingStroke() {
        if hasActiveStroke { state = .cancelled }
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                           shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        TabletEventKind.classify(event) == .point
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldReceive touch: NSTouch) -> Bool {
        false
    }

    override func reset() {
        super.reset()
        penEvent = nil
    }

    override func location(in view: NSView?) -> NSPoint {
        guard let event = penEvent else { return .zero }
        return view?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
    }

    override func canPrevent(_ preventedGestureRecognizer: NSGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: NSGestureRecognizer) -> Bool { false }
}
