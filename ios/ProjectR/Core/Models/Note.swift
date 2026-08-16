import Foundation

/// A short, public, project-independent text note — closer to a tweet
/// than a devlog entry. Posted from the Add tab, shown on the author's
/// profile in the Notes tab (and, since it's public like everything but
/// `saves`, on other people's profiles too).
struct Note: Codable, Identifiable, Hashable {
    let id: UUID
    var authorID: UUID
    var body: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case body
        case createdAt = "created_at"
    }
}
