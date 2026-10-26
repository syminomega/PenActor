import SwiftUI

struct PencilInteractionObserver: ViewModifier {
    let monitor: PenMonitor

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14.5, *) {
            content
                .onPencilDoubleTap { _ in monitor.recordPencilDoubleTap(source: .swiftUI) }
                .onPencilSqueeze { phase in
                    switch phase {
                    case .active: monitor.recordPencilSqueeze(.active)
                    case .ended: monitor.recordPencilSqueeze(.ended)
                    case .failed: monitor.recordPencilSqueeze(.failed)
                    }
                }
        } else {
            content
        }
    }
}
