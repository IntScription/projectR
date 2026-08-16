import Foundation

struct ChatMessage: Codable, Identifiable, Hashable {
    let id: UUID
    var conversationID: UUID
    var senderID: UUID
    var body: String
    var createdAt: Date
    var readAt: Date?
    var metadata: ForgeShareMetadata?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationID = "conversation_id"
        case senderID = "sender_id"
        case body
        case createdAt = "created_at"
        case readAt = "read_at"
        case metadata
    }
}

/// A rich-card payload for sharing a Forge object (a commit, for now) in
/// chat — carried in `messages.metadata` (a nullable jsonb column) rather
/// than a new message type/table. `body` still carries a plain-text
/// fallback of the same content, so older clients (or anything that only
/// ever reads `body`) degrade gracefully to a tappable link instead of
/// silently showing nothing.
struct ForgeShareMetadata: Codable, Hashable {
    var kind: String
    var githubURL: String
    var projectID: UUID
    var sha: String
    var title: String
    var subtitle: String

    enum CodingKeys: String, CodingKey {
        case kind
        case githubURL = "github_url"
        case projectID = "project_id"
        case sha, title, subtitle
    }
}
