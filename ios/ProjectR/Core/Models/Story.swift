import Foundation

/// The Swift-side counterpart to the `media_type` Postgres enum — kept as
/// its own type (rather than a raw string everywhere) so capture/composer
/// code can switch over it exhaustively.
enum StoryMediaKind: String, Codable {
    case image, video
}

/// Raw `stories` row — used for inserts/deletes. Reads go through
/// `StoryFeedItem` (the `active_stories_feed` view) or `StoryHighlightItem`
/// instead, since both need the author's profile fields alongside it.
struct Story: Codable, Identifiable, Hashable {
    let id: UUID
    var authorID: UUID
    var mediaURL: String
    var mediaType: StoryMediaKind
    var createdAt: Date
    var expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case mediaURL = "media_url"
        case mediaType = "media_type"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}

/// Mirrors `public.active_stories_feed` — a non-expired story with its
/// author's profile fields flattened in, plus whether the signed-in user
/// has already viewed it (drives the ring's gradient-vs-gray state).
struct StoryFeedItem: Codable, Identifiable, Hashable {
    let id: UUID
    var authorID: UUID
    var mediaURL: String
    var mediaType: StoryMediaKind
    var createdAt: Date
    var expiresAt: Date
    var authorUsername: String
    var authorDisplayName: String
    var authorAvatarURL: String?
    var viewedByMe: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case mediaURL = "media_url"
        case mediaType = "media_type"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case authorUsername = "author_username"
        case authorDisplayName = "author_display_name"
        case authorAvatarURL = "author_avatar_url"
        case viewedByMe = "viewed_by_me"
    }
}

struct StoryHighlight: Codable, Identifiable, Hashable {
    let id: UUID
    var ownerID: UUID
    var title: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case title
        case createdAt = "created_at"
    }
}

/// One story inside a highlight — the join of `story_highlight_items` to
/// its underlying `stories` row (via `story:stories(*)` in the select),
/// used by the highlight viewer since highlights outlive a story's normal
/// 24h expiry and so can't be read through `active_stories_feed`.
struct StoryHighlightItem: Codable, Identifiable, Hashable {
    var highlightID: UUID
    var position: Int
    var story: Story

    var id: UUID { story.id }

    enum CodingKeys: String, CodingKey {
        case highlightID = "highlight_id"
        case position
        case story
    }
}
