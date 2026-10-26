import SwiftUI
import AppKit

struct TestPad: NSViewRepresentable {
    let isRunning: Bool
    let clearGeneration: Int

    func makeNSView(context: Context) -> PenTestView { PenTestView() }

    func updateNSView(_ view: PenTestView, context: Context) {
        view.setMonitoring(isRunning)
        if view.clearGeneration != clearGeneration {
            view.clearGeneration = clearGeneration
            view.clear()
        }
    }

    static func dismantleNSView(_ view: PenTestView, coordinator: ()) { view.tearDown() }
}

