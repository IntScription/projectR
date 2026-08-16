import Foundation

enum ProjectCategory: String, Codable, CaseIterable, Identifiable {
    case software, ai, games, design, music, art, hardware, writing, research, other
    var id: String { rawValue }
}

enum ProjectStatus: String, Codable, CaseIterable, Identifiable {
    case idea, building, testing, launched, maintaining, archived
    var id: String { rawValue }
}

struct Project: Codable, Identifiable, Hashable {
    let id: UUID
    var ownerID: UUID
    var slug: String
    var name: String
    var description: String?
    /// AI-authored portfolio bio — deliberately separate from
    /// `description` (the owner's own words, shown everywhere else) so
    /// generating one is an explicit, reviewable action from the
    /// create/edit flow, never a silent overwrite. See
    /// `ProjectBioGenerator`/`AIBioGeneratorSection`.
    var aiSummary: String?
    var coverImageURL: String?
    var coverVideoURL: String?
    var category: ProjectCategory
    var tags: [String]
    var status: ProjectStatus
    var techStack: [String]
    var githubURL: String?
    /// Anything besides GitHub — website, App Store, demo, docs, etc.
    /// `github_url` stays its own column since it drives the fork/verified
    /// badge features, not just display.
    var links: [ProfileLink]
    var isOpenSource: Bool
    var viewCount: Int
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case slug, name, description
        case aiSummary = "ai_summary"
        case coverImageURL = "cover_image_url"
        case coverVideoURL = "cover_video_url"
        case category, tags, status
        case techStack = "tech_stack"
        case githubURL = "github_url"
        case links
        case isOpenSource = "is_open_source"
        case viewCount = "view_count"
        case createdAt = "created_at"
    }
}
