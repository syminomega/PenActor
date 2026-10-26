import SwiftUI

struct PressureTrend: View {
    let events: [PenEvent]

    var body: some View {
        Canvas { context, size in
            let end = events.last?.timestamp ?? 0
            let start = end - 5
            var grid = Path()
            for fraction in [0.0, 0.5, 1.0] {
                let y = fraction * size.height
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(.secondary.opacity(0.2)), lineWidth: 1)
            var path = Path()
            var previousTime: TimeInterval?
            for event in events where event.timestamp >= start {
                guard let pressure = event.sample?.pressure else { previousTime = nil; continue }
                let point = CGPoint(x: (event.timestamp - start) / 5 * size.width,
                                    y: (1 - Double(max(0, min(1, pressure)))) * size.height)
                if let previousTime, event.timestamp - previousTime < 0.25 { path.addLine(to: point) }
                else { path.move(to: point) }
                previousTime = event.timestamp
            }
            context.stroke(path, with: .color(.accentColor), lineWidth: 2)
        }
    }
}
