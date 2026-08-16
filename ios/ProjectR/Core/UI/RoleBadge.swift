import SwiftUI

/// A profile's role tag (e.g. "ProjectR Developer") — a solid gradient
/// capsule rather than the accent-tinted style used elsewhere, so it reads
/// as a distinct "credential" next to the display name instead of blending
/// into the app's usual orange accent.
struct RoleBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing),
                in: Capsule()
            )
            .foregroundStyle(.white)
    }
}
