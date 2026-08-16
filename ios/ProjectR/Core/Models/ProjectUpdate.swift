import Foundation

struct ProjectUpdate: Codable, Identifiable, Hashable {
    let id: UUID
    var projectID: UUID
    var body: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case body
        case createdAt = "created_at"
    }
}
