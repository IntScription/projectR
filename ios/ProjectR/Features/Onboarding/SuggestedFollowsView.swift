import SwiftUI

/// Shown once, right after onboarding finishes — a brand-new account has
/// nobody to follow yet, so Home's feed and Discover's "Following" mode
/// would otherwise be empty on first launch. Reuses `suggested_profiles`,
/// which already falls back to overall popularity when there's no follow
/// graph to walk yet (exactly this cold-start case). Skippable — this is
/// a nudge, not a gate.
struct SuggestedFollowsView: View {
    var onDone: () -> Void

    @State private var profiles: [Profile] = []
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Follow a few builders")
                    .font(.title2.bold())
                Text("Your Home feed and Discover get better once you're following people.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            .padding(.horizontal, 32)

            if isLoading && profiles.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if profiles.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "Nobody to suggest yet", systemImage: "person.2",
                    description: Text("You're one of the first here — check back once more people join."))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(profiles) { profile in
                            SuggestedFollowRow(profile: profile)
                        }
                    }
                    .padding(20)
                }
            }

            Button {
                onDone()
            } label: {
                Text("Continue")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        profiles =
            (try? await SupabaseManager.shared.client
                .rpc("suggested_profiles", params: ["limit_count": 15])
                .execute()
                .value) ?? []
    }
}

private struct SuggestedFollowRow: View {
    let profile: Profile

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: profile.avatarURL.flatMap(URL.init)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Color.accentColor.opacity(0.2)).overlay(
                    Text(profile.displayName.prefix(1).uppercased())
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                )
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName).font(.subheadline.weight(.semibold))
                Text("@\(profile.username)").font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            FollowButton(target: .profile(profile.id))
                .controlSize(.small)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
