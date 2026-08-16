import Supabase
import SwiftUI

/// Generated reward art for an achievement — a gradient in the
/// achievement's own rank color with its icon watermarked large behind
/// the title. There's no illustrated-artwork pipeline in this app, so
/// this is rendered to a real image on-device via `ImageRenderer` rather
/// than referencing a bundled asset — the same view doubles as the small
/// in-sheet preview and the source for the actual uploaded banner.
struct AchievementBannerArtView: View {
    let achievement: Achievement

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [achievement.color, achievement.color.opacity(0.55), Color.black.opacity(0.85)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: achievement.icon)
                .font(.system(size: 140, weight: .bold))
                .foregroundStyle(.white.opacity(0.16))
                .offset(x: 90, y: -20)

            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Text(achievement.rank.uppercased())
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.75))
                Text(achievement.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipped()
    }
}

enum AchievementRewardError: LocalizedError {
    case renderFailed
    var errorDescription: String? { "Couldn't generate the reward art — try again." }
}

/// Same 3:1-ish proportions `ProfileView`'s real banner slot displays at
/// (full width, ~130pt tall) — rendered at 1200x400 so it stays crisp
/// once `AsyncImage`'s `.scaledToFill()` stretches it back down.
enum AchievementReward_Art {
    @MainActor
    static func renderBannerJPEG(for achievement: Achievement) -> Data? {
        let renderer = ImageRenderer(
            content: AchievementBannerArtView(achievement: achievement).frame(width: 1200, height: 400))
        renderer.scale = 2
        guard let uiImage = renderer.uiImage else { return nil }
        return uiImage.jpegData(compressionQuality: 0.85)
    }

    /// Reuses `ProfileView.updateBanner()`'s exact upload path (same
    /// bucket, same path convention, same `profiles.banner_url` update) —
    /// a reward banner is just a real banner, not a separate concept.
    @MainActor
    static func applyAsBanner(_ achievement: Achievement, profile: Binding<Profile>) async throws {
        guard let data = renderBannerJPEG(for: achievement) else {
            throw AchievementRewardError.renderFailed
        }
        let path = "\(profile.wrappedValue.id)/banner.jpg"
        let storage = SupabaseManager.shared.client.storage.from(SupabaseBucket.avatars)
        try await storage.upload(
            path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        let url = try storage.getPublicURL(path: path).absoluteString + "?v=\(Int(Date().timeIntervalSince1970))"

        let updated: Profile =
            try await SupabaseManager.shared.client
            .from("profiles")
            .update(["banner_url": url])
            .eq("id", value: profile.wrappedValue.id)
            .select()
            .single()
            .execute()
            .value
        profile.wrappedValue = updated
    }
}
