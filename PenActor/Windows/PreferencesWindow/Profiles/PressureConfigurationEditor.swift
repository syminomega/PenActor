import SwiftUI

struct PressureConfigurationEditor: View {
    @Binding var configuration: PressureConfiguration
    var component: ConfigurationComponent? = nil
    @State private var selectedPoint: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if component == nil || component == .curve { curveControls }
            if component != .curve {
                VStack(alignment: .leading, spacing: 10) {
                    if component == nil { Text(String(localized: "Stroke tapering")).font(.headline) }
                    if component == nil || component == .entry { entryControls }
                    if component == nil { Divider() }
                    if component == nil || component == .exit { exitControls }
                    if component == nil {
                        Button(String(localized: "Taper Test Preset")) {
                            configuration.taper = StrokeTaperSettings(entryEnabled: true, entryDistance: 12,
                                entryDurationMS: 60, exitEnabled: true, exitDurationMS: 60)
                        }
                    }
                }.toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var curveControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Pressure curve")).font(.headline)
            PressureCurveEditor(curve: $configuration.curve, selected: $selectedPoint)
                .frame(width: 230, height: 180)
            HStack {
                Button(String(localized: "Linear")) { configuration.curve = .linear; selectedPoint = nil }
                Button(String(localized: "Light Pressure")) { configuration.curve = .light; selectedPoint = nil }
                Button(String(localized: "Delete Point")) {
                    guard let i = selectedPoint, i > 0, i < configuration.curve.points.count-1 else { return }
                    configuration.curve.points.remove(at: i); selectedPoint = nil
                }.disabled(selectedPoint == nil || selectedPoint == 0 || selectedPoint == configuration.curve.points.count-1)
            }
            Text(String(localized: "Double-click to add a point; drag to adjust. Input is horizontal, output vertical. Endpoints are fixed."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .frame(width: 230, alignment: .leading)
        }
    }

    private var entryControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(String(localized: "Entry taper · Fade in from zero pressure"), isOn: $configuration.taper.entryEnabled)
            if configuration.taper.entryEnabled {
                parameter(String(localized: "Entry length"), value: $configuration.taper.entryDistance, range: 1...200, step: 1, unit: String(localized: "pt"))
                parameter(String(localized: "Time limit"), value: $configuration.taper.entryDurationMS, range: 10...500, step: 5, unit: "ms")
                Text(String(localized: "Entry taper ends when the distance or time limit is reached. Very short strokes may fade."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var exitControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(String(localized: "Exit taper · Buffer and fade the tail"), isOn: $configuration.taper.exitEnabled)
            if configuration.taper.exitEnabled {
                parameter(String(localized: "Delay"), value: $configuration.taper.exitDurationMS, range: 10...200, step: 5, unit: "ms")
                Text(String(localized: "Delays pen input and tapers the queued tail after lift-off. Shortcuts flush the queue early."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func parameter(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).frame(width: 62, alignment: .leading)
            Slider(value: Binding(
                get: { value.wrappedValue },
                set: { raw in
                    let snapped = range.lowerBound + ((raw-range.lowerBound)/step).rounded()*step
                    value.wrappedValue = min(range.upperBound, max(range.lowerBound, snapped))
                }
            ), in: range)
            Text("\(value.wrappedValue, specifier: "%.0f") \(unit)").font(.caption.monospacedDigit())
                .foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
        }
    }
}
