import Foundation

/// Mirrors `public.profile_updates_feed` — one row per update with its
/// first media item flattened in, for the Instagram-grid "Posts" tab.
struct ProfileUpdateFeedItem: Codable, Identifiable, Hashable {
    let id: UUID
    var projectID: UUID
    var body: String
    var createdAt: Date
    var ownerID: UUID
    var projectSlug: String
    var projectName: String
    var mediaURL: String?
    var mediaType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case body
        case createdAt = "created_at"
        case ownerID = "owner_id"
        case projectSlug = "project_slug"
        case projectName = "project_name"
        case mediaURL = "media_url"
        case mediaType = "media_type"
    }
}
