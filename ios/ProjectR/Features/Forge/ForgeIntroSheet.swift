import SwiftUI

/// Shown once, right after GitHub connects for the first time — the
/// moment the Forge tab actually becomes reachable, so this is the
/// natural place to explain what it does rather than leaving someone to
/// discover a new tab icon and guess. Deliberately a one-time event tied
/// to the connect action itself (see `RootTabView`'s
/// `.gitHubDidConnect` observer), not something re-shown on every launch.
struct ForgeIntroSheet: View {
    var onExplore: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let features: [(icon: String, title: String, detail: String)] = [
        ("folder.fill", "Browse your code", "Files, commits, and branches — right where your project already lives."),
        ("arrow.triangle.branch", "Turn tasks into branches", "Create a branch straight from a task, no terminal required."),
        ("arrow.triangle.pull", "Open pull requests", "Push a task from branch to PR without leaving ProjectR."),
        ("bubble.left.and.bubble.right.fill", "Share what you shipped", "Send a commit or PR into a chat as a real, tappable card."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    VStack(spacing: 14) {
                        ForEach(features, id: \.title) { feature in
                            featureRow(feature)
                        }
                    }
                }
                .padding(24)
            }

            VStack(spacing: 10) {
                Button {
                    dismiss()
                    onExplore()
                } label: {
                    Text("Explore Forge")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Maybe later") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "hammer.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)

            Text("GitHub is connected — Forge is ready")
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            Text("A new tab just showed up. Forge connects each of your projects to its repository, so shipping code and sharing progress can happen in the same place.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func featureRow(_ feature: (icon: String, title: String, detail: String)) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: feature.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title).font(.subheadline.weight(.semibold))
                Text(feature.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
