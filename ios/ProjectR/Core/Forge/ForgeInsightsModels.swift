import Foundation

/// One week of `GET /repos/{o}/{r}/stats/commit_activity` — GitHub's own
/// rolling 52-week commit histogram, computed and refreshed by GitHub
/// itself server-side (this app stores none of it).
struct ForgeCommitActivityWeek: Decodable, Identifiable, Hashable {
    var weekStart: Date
    var total: Int

    var id: Date { weekStart }

    private enum CodingKeys: String, CodingKey { case week, total }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekStart = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .week))
        total = try container.decode(Int.self, forKey: .total)
    }
}

/// One week of `GET /repos/{o}/{r}/stats/code_frequency` — GitHub encodes
/// each week as a bare `[week, additions, deletions]` triple, not a keyed
/// object, so this decodes from an unkeyed container instead of the usual
/// `CodingKeys` shape.
struct ForgeCodeFrequencyWeek: Decodable, Identifiable, Hashable {
    var weekStart: Date
    var additions: Int
    /// Already negative in GitHub's response (a real deletion count
    /// expressed as a negative delta), kept as-is so a diverging chart can
    /// plot it directly below zero without re-deriving the sign.
    var deletions: Int

    var id: Date { weekStart }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        weekStart = Date(timeIntervalSince1970: try container.decode(Double.self))
        additions = try container.decode(Int.self)
        deletions = try container.decode(Int.self)
    }
}

/// `GET /repos/{o}/{r}/stats/contributors` — total commits per
/// contributor over the repo's full history.
struct ForgeContributorStat: Decodable, Identifiable, Hashable {
    var login: String
    var avatarURL: String?
    var total: Int

    var id: String { login }

    private struct Author: Decodable {
        var login: String?
        var avatarURL: String?
        enum CodingKeys: String, CodingKey { case login, avatarURL = "avatar_url" }
    }
    private enum CodingKeys: String, CodingKey { case author, total }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let author = try container.decodeIfPresent(Author.self, forKey: .author)
        login = author?.login ?? "Unknown"
        avatarURL = author?.avatarURL
        total = try container.decode(Int.self, forKey: .total)
    }
}

/// One `[day(0=Sun...6=Sat), hour(0-23), commits]` triple from
/// `GET /repos/{o}/{r}/stats/punch_card`.
struct ForgePunchCardEntry: Decodable, Hashable {
    var day: Int
    var hour: Int
    var commits: Int

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        day = try container.decode(Int.self)
        hour = try container.decode(Int.self)
        commits = try container.decode(Int.self)
    }
}

/// `GET /repos/{o}/{r}/languages` — bytes per language. Distinct from
/// `GitHubService.languages`, which already exists for a different job
/// (auto-filling a new project's tech stack) and discards the byte counts
/// this needs to render real proportions.
struct ForgeLanguageBytes: Identifiable, Hashable {
    var language: String
    var bytes: Int

    var id: String { language }
}

/// Derived client-side from up to 100 recent issues — GitHub's REST API
/// doesn't summarize velocity itself.
struct ForgeIssueVelocity: Hashable {
    var openCount: Int
    var closedCount: Int
    var averageDaysToClose: Double?
}

/// Same idea as `ForgeIssueVelocity`, for pull requests — merge rate is
/// merged / (merged + closed-without-merge), `nil` when nothing's closed
/// yet rather than shown as a misleading 0%.
struct ForgePullRequestVelocity: Hashable {
    var openCount: Int
    var mergedCount: Int
    var closedWithoutMergeCount: Int
    var averageDaysToMerge: Double?
    var mergeRate: Double?
}

/// One row of `repo_analytics_snapshots` — our own weekly point-in-time
/// capture of metadata GitHub itself doesn't expose historically (star
/// count, open-issue count over time). Read directly via Supabase, not
/// through `GitProvider` — this is our data, not GitHub's.
///
/// `captured_at` is a plain SQL `date` column (`"2026-08-16"`, no time
/// component) — decoded as `String` rather than `Date` deliberately, since
/// the Supabase client's default decoder only understands full ISO 8601
/// timestamps and would fail on a bare date string.
struct ForgeRepoAnalyticsSnapshot: Decodable, Identifiable, Hashable {
    var capturedAtRaw: String
    var stars: Int
    var openIssues: Int
    var forks: Int
    var watchers: Int

    var id: String { capturedAtRaw }

    var capturedAt: Date? {
        Self.dateFormatter.date(from: capturedAtRaw)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    enum CodingKeys: String, CodingKey {
        case capturedAtRaw = "captured_at"
        case stars
        case openIssues = "open_issues"
        case forks, watchers
    }
}
