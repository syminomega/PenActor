import SwiftUI

/// A live meter, not an animated task-progress indicator. Canvas draws the latest value directly.
struct PressureLevelBar: View {
    let pressure: Double?
    private var fraction: Double {
        guard let pressure, pressure.isFinite else { return 0 }
        return min(1, max(0, pressure))
    }
    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let track = Path(roundedRect: bounds, cornerRadius: size.height / 2)
            context.fill(track, with: .color(.secondary.opacity(0.12)))
            context.stroke(track, with: .color(.secondary.opacity(0.2)), lineWidth: 0.5)
            let width = size.width * fraction
            if width > 0 {
                let fill = Path(roundedRect: CGRect(x: 0, y: 0, width: width, height: size.height), cornerRadius: min(size.height / 2, width / 2))
                context.fill(fill, with: .color(.accentColor))
            }
        }
        .frame(height: 8)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "压力"))
        .accessibilityValue(pressure?.isFinite == true ? fraction.formatted(.percent.precision(.fractionLength(1))) : String(localized: "未取得"))
    }
}
