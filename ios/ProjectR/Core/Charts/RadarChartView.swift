import SwiftUI

/// Hand-built spider/radar chart for visualizing strengths vs. weaknesses
/// across the level formula's weighted components. SwiftUI's `Charts`
/// framework has no radar chart type, so this is a plain `Canvas` drawing —
/// same approach as `CodeParticlesBackground` elsewhere in the app.
struct RadarChartView: View {
    struct Axis {
        var name: String
        var value: Double // 0...100
        var color: Color = .accentColor
    }

    var axes: [Axis]

    private let ringCount = 4
    private let margin: CGFloat = 34

    var body: some View {
        Canvas { context, size in
            let count = axes.count
            guard count >= 3 else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - margin

            func point(index: Int, fraction: CGFloat) -> CGPoint {
                let angle = (CGFloat(index) / CGFloat(count)) * 2 * .pi - .pi / 2
                return CGPoint(
                    x: center.x + cos(angle) * radius * fraction,
                    y: center.y + sin(angle) * radius * fraction
                )
            }

            for ring in 1...ringCount {
                let fraction = CGFloat(ring) / CGFloat(ringCount)
                var path = Path()
                for i in 0..<count {
                    let p = point(index: i, fraction: fraction)
                    i == 0 ? path.move(to: p) : path.addLine(to: p)
                }
                path.closeSubpath()
                context.stroke(path, with: .color(.primary.opacity(0.08)), lineWidth: 1)
            }

            for i in 0..<count {
                var path = Path()
                path.move(to: center)
                path.addLine(to: point(index: i, fraction: 1))
                context.stroke(path, with: .color(.primary.opacity(0.12)), lineWidth: 1)
            }

            var dataPath = Path()
            for i in 0..<count {
                let fraction = CGFloat(max(0, min(axes[i].value, 100))) / 100
                let p = point(index: i, fraction: fraction)
                i == 0 ? dataPath.move(to: p) : dataPath.addLine(to: p)
            }
            dataPath.closeSubpath()

            // A conic blend of every axis's own color, rather than one flat
            // fill — the shape's color reads as "made of" its components,
            // not just a generic silhouette.
            let ringColors = axes.map(\.color) + [axes[0].color]
            context.fill(
                dataPath,
                with: .conicGradient(
                    Gradient(colors: ringColors.map { $0.opacity(0.35) }),
                    center: center, angle: .degrees(-90)
                )
            )
            context.stroke(dataPath, with: .color(.primary.opacity(0.4)), lineWidth: 1.5)

            for i in 0..<count {
                let fraction = CGFloat(max(0, min(axes[i].value, 100))) / 100
                let p = point(index: i, fraction: fraction)
                let dot = Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                context.fill(dot, with: .color(axes[i].color))
                context.stroke(dot, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
            }

            for i in 0..<count {
                let labelPoint = point(index: i, fraction: 1.18)
                context.draw(
                    Text(axes[i].name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(axes[i].color),
                    at: labelPoint
                )
            }
        }
        .frame(height: 250)
    }
}
