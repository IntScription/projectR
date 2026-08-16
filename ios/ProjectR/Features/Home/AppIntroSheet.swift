import SwiftUI

/// A short "here's what this is" explainer — shown once per app version,
/// to both brand-new users (right after their first sign-in, since this
/// lives on `RootTabView`, mounted the same way either case) and existing
/// users after an update (see `RootTabView`'s `lastSeenIntroVersion`
/// comparison against the real bundle version). Same fixed-bottom-CTA
/// sheet shape as `ForgeIntroSheet` — "Skip" and the primary action both
/// just dismiss, since there's nothing this sheet gates access to.
struct AppIntroSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let features: [(icon: String, title: String, detail: String)] = [
        (
            "square.stack.3d.up.fill", "Projects, not posts",
            "Everything here belongs to a project — no generic feed of random updates about nothing."
        ),
        (
            "hammer.fill", "Forge",
            "A real dev workspace inside the app — browse commits, open PRs, and see repo insights without leaving."
        ),
        (
            "doc.richtext.fill", "Portfolio PDF",
            "Turn your best projects into a real, shareable PDF — auto-filled bios and real GitHub stats included."
        ),
        (
            "chart.bar.fill", "Levels that mean something",
            "Your level comes from what you've actually shipped — not follower counts."
        ),
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
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Skip") { dismiss() }
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
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)

            Text("Welcome to ProjectR")
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            Text("A project-first network for developers — your profile is a portfolio with a pulse, not a stream of the self.")
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
