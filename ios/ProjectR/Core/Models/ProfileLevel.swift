import Foundation

/// Mirrors `public.profile_levels` — computed server-side by the
/// rule-based `refresh_profile_level` function from real project data
/// (tech stack diversity, shipped projects, updates, engagement), not an
/// LLM call. `get_profile_level` lazily recomputes it once a day.
struct ProfileLevel: Codable, Hashable {
    var profileID: UUID
    var level: Int
    var levelLabel: String
    var score: Int
    var skills: [Skill]
    var projectsAnalyzed: Int
    var summary: String
    var breakdown: [Component]
    var notes: [String]
    var computedAt: Date

    /// `level` is that skill's own 1-100 score — the same shape as the
    /// overall level formula, just scoped to only the projects using this
    /// one tech, so it isn't just a raw project count.
    struct Skill: Codable, Hashable, Identifiable {
        var name: String
        var level: Int
        var projects: Int
        var id: String { name }
    }

    /// One weighted signal in the level formula — `score` is a 0-100 ratio
    /// against that signal's own cap (e.g. shipped-vs-total projects),
    /// `weight` is its percentage contribution to the final total, so the
    /// dashboard can show the actual math rather than an opaque number.
    struct Component: Codable, Hashable, Identifiable {
        var name: String
        var score: Int
        var weight: Int
        var id: String { name }
    }

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case level
        case levelLabel = "level_label"
        case score, skills
        case projectsAnalyzed = "projects_analyzed"
        case summary, breakdown, notes
        case computedAt = "computed_at"
    }
}

private struct TargetProfileParams: Encodable {
    let targetProfileID: UUID
    enum CodingKeys: String, CodingKey {
        case targetProfileID = "target_profile_id"
    }
}

enum ProfileLevelService {
    static func fetch(profileID: UUID) async -> ProfileLevel? {
        try? await SupabaseManager.shared.client
            .rpc("get_profile_level", params: TargetProfileParams(targetProfileID: profileID))
            .execute()
            .value
    }
}
