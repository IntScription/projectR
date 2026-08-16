import Foundation

/// Mirrors `conversations`. `userOneID < userTwoID` is enforced in the DB
/// (an ordering check + unique index), so there's exactly one row per pair
/// of users regardless of who started it — `otherParticipant` is how the
/// UI recovers "the person who isn't me" from that ordered pair.
struct Conversation: Codable, Identifiable, Hashable {
    let id: UUID
    var userOneID: UUID
    var userTwoID: UUID
    var lastMessageAt: Date?
    var createdAt: Date
    var theme: String
    var userOne: UserSummary
    var userTwo: UserSummary

    enum CodingKeys: String, CodingKey {
        case id
        case userOneID = "user_one_id"
        case userTwoID = "user_two_id"
        case lastMessageAt = "last_message_at"
        case createdAt = "created_at"
        case theme
        case userOne = "user_one"
        case userTwo = "user_two"
    }

    func otherParticipant(currentUserID: UUID) -> (id: UUID, summary: UserSummary) {
        userOneID == currentUserID ? (userTwoID, userTwo) : (userOneID, userOne)
    }
}
