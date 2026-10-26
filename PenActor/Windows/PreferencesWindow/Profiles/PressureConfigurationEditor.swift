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
                    if component == nil { Text(String(localized: "入锋与出锋")).font(.headline) }
                    if component == nil || component == .entry { entryControls }
                    if component == nil { Divider() }
                    if component == nil || component == .exit { exitControls }
                    if component == nil {
                        Button(String(localized: "首尾测试预设")) {
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
            Text(String(localized: "压力曲线")).font(.headline)
            PressureCurveEditor(curve: $configuration.curve, selected: $selectedPoint)
                .frame(width: 230, height: 180)
            HStack {
                Button(String(localized: "线性")) { configuration.curve = .linear; selectedPoint = nil }
                Button(String(localized: "轻压增强")) { configuration.curve = .light; selectedPoint = nil }
                Button(String(localized: "删除点")) {
                    guard let i = selectedPoint, i > 0, i < configuration.curve.points.count-1 else { return }
                    configuration.curve.points.remove(at: i); selectedPoint = nil
                }.disabled(selectedPoint == nil || selectedPoint == 0 || selectedPoint == configuration.curve.points.count-1)
            }
            Text(String(localized: "双击添加控制点，拖动调整。横轴输入，纵轴输出；端点固定。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .frame(width: 230, alignment: .leading)
        }
    }

    private var entryControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(String(localized: "入锋 · 从零压力平滑进入"), isOn: $configuration.taper.entryEnabled)
            if configuration.taper.entryEnabled {
                parameter(String(localized: "入锋长度"), value: $configuration.taper.entryDistance, range: 1...200, step: 1, unit: String(localized: "点"))
                parameter(String(localized: "时间上限"), value: $configuration.taper.entryDurationMS, range: 10...500, step: 5, unit: "ms")
                Text(String(localized: "累计屏幕距离或时间先达到者结束入锋；很短的点画可能变淡。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var exitControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(String(localized: "出锋 · 缓冲尾部并渐隐"), isOn: $configuration.taper.exitEnabled)
            if configuration.taper.exitEnabled {
                parameter(String(localized: "时长 / 延迟"), value: $configuration.taper.exitDurationMS, range: 10...200, step: 5, unit: "ms")
                Text(String(localized: "会延迟笔输入，抬笔后修整尚未输出的尾部。快捷键会提前排空缓存。"))
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
