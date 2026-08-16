import Foundation

/// Mirrors the `project_feed` view — one row shape backs New, Trending,
/// Categories, and Search, since it's the same underlying view with a
/// different ORDER BY / WHERE from the client. Owner fields are flattened
/// rather than embedded, because the view has no foreign key for PostgREST
/// to embed through.
struct DiscoverProject: Codable, Identifiable, Hashable {
    let id: UUID
    var slug: String
    var name: String
    var description: String?
    var category: ProjectCategory
    var status: ProjectStatus
    var createdAt: Date
    var ownerID: UUID
    var ownerUsername: String
    var ownerDisplayName: String
    var ownerAvatarURL: String?
    var likeCount: Int
    var commentCount: Int
    var trendingScore: Double
    var coverImageURL: String?
    var isLikedByMe: Bool = false
    var coverVideoURL: String?

    enum CodingKeys: String, CodingKey {
        case id, slug, name, description, category, status
        case createdAt = "created_at"
        case ownerID = "owner_id"
        case ownerUsername = "owner_username"
        case ownerDisplayName = "owner_display_name"
        case ownerAvatarURL = "owner_avatar_url"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case trendingScore = "trending_score"
        case coverImageURL = "cover_image_url"
        case isLikedByMe = "is_liked_by_me"
        case coverVideoURL = "cover_video_url"
    }
}
