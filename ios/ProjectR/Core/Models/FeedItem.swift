import Foundation

/// Mirrors the `following_feed` view — a reverse-chron union of updates and
/// new projects from whoever the caller follows.
struct FeedItem: Codable, Identifiable, Hashable {
    enum ItemType: String, Codable {
        case update
        case newProject = "new_project"
    }

    let id: UUID
    var itemType: ItemType
    var projectID: UUID
    var projectSlug: String
    var projectName: String
    var ownerID: UUID
    var ownerUsername: String
    var ownerDisplayName: String
    var text: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case itemType = "item_type"
        case projectID = "project_id"
        case projectSlug = "project_slug"
        case projectName = "project_name"
        case ownerID = "owner_id"
        case ownerUsername = "owner_username"
        case ownerDisplayName = "owner_display_name"
        case text
        case createdAt = "created_at"
    }
}
