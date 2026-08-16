import Foundation

struct Comment: Codable, Identifiable, Hashable {
    let id: UUID
    var userID: UUID
    var projectID: UUID?
    var updateID: UUID?
    var body: String
    var createdAt: Date
    var author: UserSummary

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case projectID = "project_id"
        case updateID = "update_id"
        case body
        case createdAt = "created_at"
        case author
    }
}

/// The small "who" shape used wherever a list embeds someone's identity —
/// a comment's author, a project's owner, a search result.
struct UserSummary: Codable, Hashable {
    var username: String
    var displayName: String
    var avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
    }
}
