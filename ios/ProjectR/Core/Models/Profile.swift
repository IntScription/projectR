import Foundation

struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    var username: String
    var displayName: String
    var avatarURL: String?
    var bannerURL: String?
    var bio: String?
    var skills: [String]
    var links: [ProfileLink]
    var role: String?
    /// Not a real roles/permissions system — a single flag gating the
    /// moderation queue, flipped directly in the database for whoever's
    /// actually operating this app. Defaults `false` so every existing
    /// call site that constructs a `Profile` without it still compiles.
    var isAdmin: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case bannerURL = "banner_url"
        case bio, skills, links, role
        case isAdmin = "is_admin"
    }
}

struct ProfileLink: Codable, Hashable {
    var label: String
    var url: String
}
