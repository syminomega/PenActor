import SwiftUI

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
                Text(String(localized: "输出 100%")).font(.caption2).offset(x: 0, y: -5)
                Text("0%").font(.caption2).position(x: origin.x, y: origin.y+size.height+12)
                Text(String(localized: "输入压力")).font(.caption2).position(x: origin.x+size.width/2, y: origin.y+size.height+12)
                Text("100%").font(.caption2).position(x: origin.x+size.width-10, y: origin.y+size.height+12)
            }.coordinateSpace(name: "curve")
        }
    }
}
