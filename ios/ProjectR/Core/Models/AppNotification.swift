import Foundation

// Named `AppNotification` rather than `Notification` — that name is already
// taken by Foundation.
struct AppNotification: Codable, Identifiable, Hashable {
    enum NotificationType: String, Codable {
        case follow, like, comment, update
        case newProject = "new_project"
        case note
    }

    let id: UUID
    var actorID: UUID
    var type: NotificationType
    var projectID: UUID?
    var updateID: UUID?
    var commentID: UUID?
    var noteID: UUID?
    var isRead: Bool
    var createdAt: Date
    var actor: UserSummary

    enum CodingKeys: String, CodingKey {
        case id
        case actorID = "actor_id"
        case type
        case projectID = "project_id"
        case updateID = "update_id"
        case commentID = "comment_id"
        case noteID = "note_id"
        case isRead = "is_read"
        case createdAt = "created_at"
        case actor
    }
}
