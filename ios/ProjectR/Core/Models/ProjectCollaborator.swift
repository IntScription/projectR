import Foundation

/// One row of `project_collaborators` with the collaborator's profile
/// embedded via PostgREST's FK-based join, so listing collaborators on a
/// project doesn't need a second round trip per row.
struct ProjectCollaborator: Codable, Identifiable, Hashable {
    var projectID: UUID
    var userID: UUID
    var addedAt: Date
    var user: UserSummary

    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case userID = "user_id"
        case addedAt = "added_at"
        case user
    }
}
