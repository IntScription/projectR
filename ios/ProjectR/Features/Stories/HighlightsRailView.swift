import SwiftUI

/// `owner`'s highlights — shown at the top of the Add tab (managing your
/// own) and on both `ProfileView` and `CreatorProfileView` (the actual
/// public-facing display, Instagram-style — `story_highlights`/
/// `story_highlight_items` are publicly readable at the RLS level, so this
/// was purely a missing UI wire-up). Tapping one opens the full-screen
/// viewer sourced from that highlight's items rather than
/// `active_stories_feed`, since highlights deliberately outlive a story's
/// normal 24h expiry. `isOwnProfile` gates the delete affordance inside
/// that viewer — defaults to `true` so the Add tab call site (always the
/// signed-in user's own) doesn't need to change. Renders nothing at all
/// when the owner has no highlights yet, rather than an empty-state
/// placeholder — this is a bonus strip, not a section that needs to
/// justify its own existence with zero content.
struct HighlightsRailView: View {
    let owner: Profile
    var isOwnProfile: Bool = true

    @State private var highlights: [HighlightWithItems] = []
    @State private var selectedHighlight: HighlightWithItems?

    var body: some View {
        Group {
            if !highlights.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(highlights) { highlight in
                            Button {
                                selectedHighlight = highlight
                            } label: {
                                VStack(spacing: 4) {
                                    cover(for: highlight)
                                    Text(highlight.title).font(.caption2).lineLimit(1)
                                }
                                .frame(width: 64)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.primary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
        }
        .fullScreenCover(item: $selectedHighlight) { highlight in
            let ordered = highlight.items.sorted { $0.position < $1.position }.map(\.story)
            StoryViewerView(
                stories: ordered, startIndex: 0, authorID: owner.id, authorUsername: owner.username,
                authorDisplayName: owner.displayName, authorAvatarURL: owner.avatarURL,
                isOwnStory: isOwnProfile,
                onDeleted: isOwnProfile ? { _ in Task { await load() } } : nil)
        }
        .task { await load() }
    }

    private func cover(for highlight: HighlightWithItems) -> some View {
        let coverStory = highlight.items.min(by: { $0.position < $1.position })?.story
        return ZStack {
            Circle().fill(Color(.tertiarySystemFill))
            if let coverStory, coverStory.mediaType == .image, let url = URL(string: coverStory.mediaURL) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .clipShape(Circle())
            } else {
                Image(systemName: "star.fill").foregroundStyle(.secondary)
            }
        }
        .frame(width: 60, height: 60)
        .overlay(Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 1))
    }

    private func load() async {
        highlights =
            (try? await SupabaseManager.shared.client
                .from("story_highlights")
                .select("id, title, items:story_highlight_items(position, story:stories(*))")
                .eq("owner_id", value: owner.id)
                .order("created_at", ascending: false)
                .execute()
                .value) ?? []
    }
}

struct HighlightWithItems: Decodable, Identifiable {
    let id: UUID
    let title: String
    let items: [ItemEmbed]

    struct ItemEmbed: Decodable {
        let position: Int
        let story: Story
    }
}
