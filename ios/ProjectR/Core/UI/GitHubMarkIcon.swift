import SwiftUI

/// The real GitHub Octocat mark (Primer Octicons' `mark-github`, MIT-licensed),
/// drawn as a `Shape` rather than bundled as an image — it fills with
/// whatever `.foregroundStyle` is set, so it sits alongside SF Symbols like
/// "gearshape" or "checkmark.seal.fill" without a mismatched tint or a
/// baked-in color from an image asset.
struct GitHubMarkIcon: Shape {
    /// Path data at GitHub's native 16x16 viewBox — scaled to fit whatever
    /// frame the caller gives it.
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 8, y: 0))
        path.addCurve(
            to: CGPoint(x: 0, y: 8), control1: CGPoint(x: 3.58, y: 0), control2: CGPoint(x: 0, y: 3.58))
        path.addCurve(
            to: CGPoint(x: 5.47, y: 15.59), control1: CGPoint(x: 0, y: 11.54), control2: CGPoint(x: 2.29, y: 14.53))
        path.addCurve(
            to: CGPoint(x: 6.02, y: 15.21), control1: CGPoint(x: 5.87, y: 15.66), control2: CGPoint(x: 6.02, y: 15.42))
        path.addCurve(
            to: CGPoint(x: 6.01, y: 13.72), control1: CGPoint(x: 6.02, y: 15.02), control2: CGPoint(x: 6.01, y: 14.39))
        path.addCurve(
            to: CGPoint(x: 3.32, y: 12.78), control1: CGPoint(x: 4.0, y: 14.09), control2: CGPoint(x: 3.48, y: 13.23))
        path.addCurve(
            to: CGPoint(x: 2.5, y: 11.65), control1: CGPoint(x: 3.23, y: 12.55), control2: CGPoint(x: 2.84, y: 11.84))
        path.addCurve(
            to: CGPoint(x: 1.68, y: 11.12), control1: CGPoint(x: 2.22, y: 11.5), control2: CGPoint(x: 1.82, y: 11.13))
        path.addCurve(
            to: CGPoint(x: 1.67, y: 11.65), control1: CGPoint(x: 1.0, y: 11.11), control2: CGPoint(x: 1.04, y: 11.87))
        path.addCurve(
            to: CGPoint(x: 2.9, y: 12.47), control1: CGPoint(x: 2.31, y: 11.86), control2: CGPoint(x: 2.76, y: 12.26))
        path.addCurve(
            to: CGPoint(x: 5.23, y: 13.13), control1: CGPoint(x: 3.62, y: 13.68), control2: CGPoint(x: 4.77, y: 13.34))
        path.addCurve(
            to: CGPoint(x: 5.74, y: 12.06), control1: CGPoint(x: 5.3, y: 12.61), control2: CGPoint(x: 5.51, y: 12.26))
        path.addCurve(
            to: CGPoint(x: 2.1, y: 8.11), control1: CGPoint(x: 3.96, y: 11.86), control2: CGPoint(x: 2.1, y: 11.17))
        path.addCurve(
            to: CGPoint(x: 2.92, y: 5.96), control1: CGPoint(x: 2.1, y: 7.24), control2: CGPoint(x: 2.41, y: 6.52))
        path.addCurve(
            to: CGPoint(x: 3.0, y: 3.84), control1: CGPoint(x: 2.84, y: 5.76), control2: CGPoint(x: 2.56, y: 4.94))
        path.addCurve(
            to: CGPoint(x: 5.2, y: 4.66), control1: CGPoint(x: 3.0, y: 3.84), control2: CGPoint(x: 3.67, y: 3.63))
        path.addCurve(
            to: CGPoint(x: 7.2, y: 4.39), control1: CGPoint(x: 5.84, y: 4.48), control2: CGPoint(x: 6.52, y: 4.39))
        path.addCurve(
            to: CGPoint(x: 9.2, y: 4.66), control1: CGPoint(x: 7.88, y: 4.39), control2: CGPoint(x: 8.56, y: 4.48))
        path.addCurve(
            to: CGPoint(x: 11.4, y: 3.84), control1: CGPoint(x: 8.73, y: 3.62), control2: CGPoint(x: 9.4, y: 3.84))
        path.addCurve(
            to: CGPoint(x: 11.48, y: 5.96), control1: CGPoint(x: 11.84, y: 4.94), control2: CGPoint(x: 11.56, y: 5.76))
        path.addCurve(
            to: CGPoint(x: 12.3, y: 8.11), control1: CGPoint(x: 11.99, y: 6.52), control2: CGPoint(x: 12.3, y: 7.24))
        path.addCurve(
            to: CGPoint(x: 8.65, y: 12.06), control1: CGPoint(x: 12.3, y: 11.18), control2: CGPoint(x: 10.43, y: 11.86))
        path.addCurve(
            to: CGPoint(x: 9.19, y: 13.53), control1: CGPoint(x: 8.94, y: 12.31), control2: CGPoint(x: 9.19, y: 12.79))
        path.addCurve(
            to: CGPoint(x: 9.18, y: 15.21), control1: CGPoint(x: 9.19, y: 13.94), control2: CGPoint(x: 9.18, y: 14.8))
        path.addCurve(
            to: CGPoint(x: 9.73, y: 15.59), control1: CGPoint(x: 9.18, y: 15.42), control2: CGPoint(x: 9.33, y: 15.67))
        path.addCurve(
            to: CGPoint(x: 16, y: 8), control1: CGPoint(x: 13.71, y: 14.53), control2: CGPoint(x: 16, y: 11.54))
        path.addCurve(
            to: CGPoint(x: 8, y: 0), control1: CGPoint(x: 16, y: 3.58), control2: CGPoint(x: 12.42, y: 0))
        path.closeSubpath()

        // Scale the fixed 16x16 path data to whatever rect SwiftUI hands us.
        let scale = min(rect.width, rect.height) / 16
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: rect.midX - 8 * scale, y: rect.midY - 8 * scale))
        return path.applying(transform)
    }
}
