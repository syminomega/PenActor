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
                    if component == nil { Text("轨迹与笔锋").font(.headline) }
                    if component == nil || component == .entry { entryControls }
                    if component == nil { Divider() }
                    if component == nil || component == .exit { exitControls }
                    if component == nil {
                        Button("首尾测试预设") {
                            configuration.taper = StrokeTaperSettings(entryEnabled: true, entryDistance: 12,
                                entryDurationMS: 60, exitEnabled: true, exitDurationMS: 60)
                        }
                        Divider()
                    }
                    if component == nil || component == .smoothing { smoothingControls }
                }.toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var curveControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("压力曲线").font(.headline)
            PressureCurveEditor(curve: $configuration.curve, selected: $selectedPoint)
                .frame(width: 230, height: 180)
            HStack {
                Button("线性") { configuration.curve = .linear; selectedPoint = nil }
                Button("轻压增强") { configuration.curve = .light; selectedPoint = nil }
                Button("删除点") {
                    guard let i = selectedPoint, i > 0, i < configuration.curve.points.count-1 else { return }
                    configuration.curve.points.remove(at: i); selectedPoint = nil
                }.disabled(selectedPoint == nil || selectedPoint == 0 || selectedPoint == configuration.curve.points.count-1)
            }
            Text("双击添加控制点，拖动调整。横轴输入，纵轴输出；端点固定。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .frame(width: 230, alignment: .leading)
        }
    }

    private var entryControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("入锋 · 从零压力平滑进入", isOn: $configuration.taper.entryEnabled)
            if configuration.taper.entryEnabled {
                parameter("入锋长度", value: $configuration.taper.entryDistance, range: 1...200, step: 1, unit: "点")
                parameter("时间上限", value: $configuration.taper.entryDurationMS, range: 10...500, step: 5, unit: "ms")
                Text("累计屏幕距离或时间先达到者结束入锋；很短的点画可能变淡。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var exitControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("出锋 · 缓冲尾部并渐隐", isOn: $configuration.taper.exitEnabled)
            if configuration.taper.exitEnabled {
                parameter("时长 / 延迟", value: $configuration.taper.exitDurationMS, range: 10...200, step: 5, unit: "ms")
                Text("会延迟笔输入，抬笔后修整尚未输出的尾部。快捷键会提前排空缓存。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var smoothingControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("平滑输入 · 减轻轨迹抖动", isOn: $configuration.smoothing.enabled)
            if configuration.smoothing.enabled {
                HStack {
                    Text("强度").font(.caption)
                    Slider(value: $configuration.smoothing.strength, in: 0...1)
                    Text("\(configuration.smoothing.strength * 100, specifier: "%.0f")%")
                        .font(.caption.monospacedDigit()).frame(width: 42)
                }
            }
            Text("实时处理位置，不额外缓存；强度越高越稳定，也可能产生跟随偏差或圆化转角。压力不受此选项影响。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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

struct PressureCurveEditor: View {
    @Binding var curve: PressureCurve
    @Binding var selected: Int?
    var body: some View {
        GeometryReader { geo in
            let size = CGSize(width: max(1, geo.size.width-40), height: max(1, geo.size.height-40))
            let origin = CGPoint(x: 30, y: 10)
            let position: (PressurePoint) -> CGPoint = { CGPoint(x: origin.x+$0.x*size.width, y: origin.y+(1-$0.y)*size.height) }
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    var grid = Path()
                    for i in 0...4 {
                        let f = Double(i)/4
                        grid.move(to: position(.init(x: f, y: 0))); grid.addLine(to: position(.init(x: f, y: 1)))
                        grid.move(to: position(.init(x: 0, y: f))); grid.addLine(to: position(.init(x: 1, y: f)))
                    }
                    context.stroke(grid, with: .color(.secondary.opacity(0.3)))
                    var line = Path()
                    for i in 0...200 { let x = Double(i)/200; let p = position(.init(x: x, y: curve.map(x))); if i == 0 { line.move(to: p) } else { line.addLine(to: p) } }
                    context.stroke(line, with: .color(.accentColor), lineWidth: 2)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { location in
                    let x = min(0.999, max(0.001, (location.x-origin.x)/size.width))
                    guard curve.points.count < 32, !curve.points.contains(where: { abs($0.x-x) < 0.005 }) else { return }
                    let i = curve.points.firstIndex { $0.x > x }!
                    let y = min(curve.points[i].y, max(curve.points[i-1].y, 1-(location.y-origin.y)/size.height))
                    curve.points.insert(.init(x: x, y: y), at: i); selected = i
                }
                ForEach(curve.points.indices, id: \.self) { i in
                    Circle().fill(selected == i ? Color.orange : Color.accentColor).frame(width: 12, height: 12)
                        .position(position(curve.points[i]))
                        .onTapGesture { selected = i }
                        .gesture(DragGesture(coordinateSpace: .named("curve")).onChanged { value in
                            selected = i
                            guard i > 0 && i < curve.points.count-1 else { return }
                            let left = curve.points[i-1], right = curve.points[i+1]
                            let gap = min(0.001, (right.x-left.x)/4)
                            curve.points[i] = .init(x: min(right.x-gap, max(left.x+gap, (value.location.x-origin.x)/size.width)),
                                y: min(right.y, max(left.y, 1-(value.location.y-origin.y)/size.height)))
                        })
                }
                Text("输出 100%").font(.caption2).offset(x: 0, y: -5)
                Text("0%").font(.caption2).position(x: origin.x, y: origin.y+size.height+12)
                Text("输入压力").font(.caption2).position(x: origin.x+size.width/2, y: origin.y+size.height+12)
                Text("100%").font(.caption2).position(x: origin.x+size.width-10, y: origin.y+size.height+12)
            }.coordinateSpace(name: "curve")
        }
    }
}
