import SwiftUI

/// An avatar with an optional Instagram-style story ring around it —
/// gradient when there's an unseen active story, flat gray when every
/// active story has been seen, no ring at all when there's no active
/// story. Purely visual; callers wrap it in whatever tap action fits
/// their context (open the viewer, open the composer, etc).
struct StoryRingAvatar: View {
    enum RingState {
        case none, seen, unseen
    }

    let avatarURL: String?
    let placeholderInitial: String
    var diameter: CGFloat = 56
    var ringState: RingState = .none

    private var ringDiameter: CGFloat { diameter + 8 }

    var body: some View {
        ZStack {
            if ringState != .none {
                Circle()
                    .stroke(ringStrokeStyle, lineWidth: 2.5)
                    .frame(width: ringDiameter, height: ringDiameter)
                // A thin background-colored gap between the avatar and the
                // ring — without it the ring sits flush against the photo,
                // which reads muddy against a busy banner/feed background.
                Circle()
                    .stroke(Color(.systemBackground), lineWidth: 3)
                    .frame(width: diameter + 3, height: diameter + 3)
            }
            avatarImage
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
        }
        .frame(width: ringDiameter, height: ringDiameter)
    }

    @ViewBuilder
    private var avatarImage: some View {
        AsyncImage(url: avatarURL.flatMap(URL.init)) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Circle().fill(Color.accentColor.opacity(0.2)).overlay(
                Text(placeholderInitial.prefix(1).uppercased())
                    .font(.system(size: diameter * 0.38, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            )
        }
    }

    private var ringStrokeStyle: AnyShapeStyle {
        switch ringState {
        case .unseen:
            AnyShapeStyle(
                AngularGradient(
                    colors: [.orange, .pink, .purple, .orange], center: .center))
        case .seen:
            AnyShapeStyle(Color.secondary.opacity(0.35))
        case .none:
            AnyShapeStyle(Color.clear)
        }
    }
}
