import SwiftUI

/// Slow-drifting code glyphs behind the auth screen — echoes the app icon's
/// `</> { } ( ) #` motif rather than being generic decoration. Positions are
/// randomized once at init and held in a stored `let`, so they stay stable
/// across body re-evaluations instead of jumping around.
struct CodeParticlesBackground: View {
    private let particles: [Particle] = Self.makeParticles()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for particle in particles {
                    let y =
                        particle.baseY * size.height
                        + sin(t * particle.speed + particle.phase) * particle.amplitude
                    let x = particle.x * size.width
                    context.draw(
                        Text(particle.symbol)
                            .font(.system(size: particle.fontSize, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color.accentColor.opacity(particle.opacity)),
                        at: CGPoint(x: x, y: y)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private struct Particle {
        let symbol: String
        let x: CGFloat
        let baseY: CGFloat
        let amplitude: CGFloat
        let speed: Double
        let phase: Double
        let fontSize: CGFloat
        let opacity: Double
    }

    private static func makeParticles() -> [Particle] {
        let symbols = ["</>", "{ }", "( )", "#", "→", "[ ]", "==", "&&", ";", "fn", "01", "*", "<>", "::"]
        return (0..<26).map { i in
            Particle(
                symbol: symbols[i % symbols.count],
                x: .random(in: 0.05...0.95),
                baseY: .random(in: 0.03...0.97),
                amplitude: .random(in: 8...24),
                speed: .random(in: 0.15...0.45),
                phase: .random(in: 0...(2 * .pi)),
                fontSize: .random(in: 15...32),
                opacity: .random(in: 0.14...0.38)
            )
        }
    }
}
