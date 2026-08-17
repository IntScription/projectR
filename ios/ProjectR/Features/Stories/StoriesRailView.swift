import Supabase
import SwiftUI

/// Home's stories rail — "Your story" first (opens the capture flow if you
/// have none, or your own viewer if you do), then people you follow with
/// an active story, unseen-first. The visibility restriction is server-
/// side (blocked pairs, via `active_stories_feed`); scoping the rail to
/// "people I follow" specifically is purely a client-side feed choice on
/// top of that, same distinction the rest of the app draws elsewhere.
struct StoriesRailView: View {
    let profile: Profile

    @State private var myGroup: AuthorStoryGroup?
    @State private var followedGroups: [AuthorStoryGroup] = []
    @State private var isPresentingCaptureMenu = false
    @State private var capturedMedia: Data?
    @State private var capturedKind: StoryMediaKind = .image
    @State private var isPresentingComposer = false
    @State private var selectedGroup: AuthorStoryGroup?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                yourStoryEntry
                ForEach(followedGroups) { group in
                    ringEntry(for: group)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .storyCaptureSourceMenu(isPresented: $isPresentingCaptureMenu) { data, kind in
            capturedMedia = data
            capturedKind = kind
            isPresentingComposer = true
        }
        .fullScreenCover(isPresented: $isPresentingComposer) {
            if let capturedMedia {
                StoryComposerView(
                    uploaderID: profile.id, mediaData: capturedMedia, mediaKind: capturedKind
                ) {
                    Task { await load() }
                }
            }
        }
        .fullScreenCover(item: $selectedGroup) { group in
            StoryViewerView(
                stories: group.stories, startIndex: 0, authorID: group.authorID,
                authorUsername: group.authorUsername, authorDisplayName: group.authorDisplayName,
                authorAvatarURL: group.authorAvatarURL, isOwnStory: group.authorID == profile.id,
                onDeleted: { _ in Task { await load() } }
            )
        }
        .task { await load() }
    }

    private var yourStoryEntry: some View {
        Button {
            if let myGroup {
                selectedGroup = myGroup
            } else {
                isPresentingCaptureMenu = true
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .bottomTrailing) {
                    StoryRingAvatar(
                        avatarURL: profile.avatarURL,
                        placeholderInitial: profile.displayName,
                        diameter: 56,
                        ringState: myGroup != nil ? .seen : .none
                    )
                    if myGroup == nil {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white, Color.accentColor)
                            .background(Circle().fill(.white))
                    }
                }
                Text("Your story").font(.caption2).lineLimit(1)
            }
            .frame(width: 64)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func ringEntry(for group: AuthorStoryGroup) -> some View {
        Button {
            selectedGroup = group
        } label: {
            VStack(spacing: 4) {
                StoryRingAvatar(
                    avatarURL: group.authorAvatarURL, placeholderInitial: group.authorDisplayName,
                    diameter: 56, ringState: group.hasUnseen ? .unseen : .seen)
                Text(group.authorUsername).font(.caption2).lineLimit(1)
            }
            .frame(width: 64)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func load() async {
        let client = SupabaseManager.shared.client
        let myID = profile.id

        let followRows: [FollowRow] =
            (try? await client
                .from("follows").select("followee_profile_id").eq("follower_id", value: myID)
                .execute().value) ?? []
        let followedIDs = followRows.compactMap(\.followeeProfileID)
        let relevantIDs = followedIDs + [myID]

        let items: [StoryFeedItem] =
            (try? await client
                .from("active_stories_feed")
                .select()
                .in("author_id", values: relevantIDs)
                .order("created_at")
                .execute()
                .value) ?? []

        var grouped: [UUID: [StoryFeedItem]] = [:]
        for item in items { grouped[item.authorID, default: []].append(item) }

        myGroup = grouped[myID].map { AuthorStoryGroup(items: $0) }
        followedGroups =
            followedIDs
            .compactMap { grouped[$0] }
            .map { AuthorStoryGroup(items: $0) }
            .sorted { $0.hasUnseen && !$1.hasUnseen }
    }
}

/// One author's ordered active stories, flattened for the viewer plus the
/// ring's seen/unseen state.
struct AuthorStoryGroup: Identifiable {
    let authorID: UUID
    let authorUsername: String
    let authorDisplayName: String
    let authorAvatarURL: String?
    let stories: [Story]
    let hasUnseen: Bool

    var id: UUID { authorID }

    init(items: [StoryFeedItem]) {
        authorID = items[0].authorID
        authorUsername = items[0].authorUsername
        authorDisplayName = items[0].authorDisplayName
        authorAvatarURL = items[0].authorAvatarURL
        stories = items.map {
            Story(
                id: $0.id, authorID: $0.authorID, mediaURL: $0.mediaURL, mediaType: $0.mediaType,
                createdAt: $0.createdAt, expiresAt: $0.expiresAt)
        }
        hasUnseen = items.contains { !$0.viewedByMe }
    }
}

private struct FollowRow: Decodable {
    let followeeProfileID: UUID?
    enum CodingKeys: String, CodingKey { case followeeProfileID = "followee_profile_id" }
}
