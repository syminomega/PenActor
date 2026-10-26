import SwiftUI
import AppKit

struct WindowConfiguration: NSViewRepresentable {
    let alwaysOnTop: Bool
    func makeNSView(context: Context) -> WindowLevelView { WindowLevelView() }
    func updateNSView(_ view: WindowLevelView, context: Context) {
        view.floating = alwaysOnTop
        view.apply()
    }
}

final class WindowLevelView: NSView {
    var floating = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }
    func apply() {
        window?.level = floating ? .floating : .normal
        window?.acceptsMouseMovedEvents = true
    }
}
