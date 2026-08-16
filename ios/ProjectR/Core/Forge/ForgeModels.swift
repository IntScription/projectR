import Foundation

/// `GET /repos/{owner}/{repo}`
struct ForgeRepo: Decodable, Hashable {
    var name: String
    var fullName: String
    var description: String?
    var defaultBranch: String
    var starCount: Int
    var openIssuesCount: Int
    var htmlURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case description
        case defaultBranch = "default_branch"
        case starCount = "stargazers_count"
        case openIssuesCount = "open_issues_count"
        case htmlURL = "html_url"
    }
}

/// One entry from `GET /repos/{owner}/{repo}/contents/{path}` when `path`
/// is a directory — GitHub returns an array of these, file and dir
/// entries mixed together.
struct ForgeTreeEntry: Decodable, Identifiable, Hashable {
    var name: String
    var path: String
    var type: String
    var size: Int
    var sha: String

    var id: String { sha }
    var isDirectory: Bool { type == "dir" }
}

/// The same `contents` endpoint, but for a single known file path — a
/// different JSON shape (one object, not an array), carrying the actual
/// base64 body.
struct ForgeFileContent: Decodable {
    var name: String
    var path: String
    var size: Int
    var encoding: String
    var content: String
    /// The blob's current sha — required as the optimistic-concurrency
    /// check when committing an edit back (`GitHubProvider.updateFile`):
    /// GitHub rejects the write if this doesn't match the file's actual
    /// current sha, which is exactly the "someone else changed this
    /// since you loaded it" guard.
    var sha: String

    /// GitHub line-wraps the base64 body at 60 characters with embedded
    /// newlines — strip those before decoding, then only return text for
    /// content that's actually valid UTF-8 (binary files decode to `nil`,
    /// which the code viewer treats as "can't preview this").
    var decodedText: String? {
        guard encoding == "base64" else { return nil }
        guard let data = Data(base64Encoded: content.replacingOccurrences(of: "\n", with: "")) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

/// `GET /repos/{owner}/{repo}/commits` — GitHub nests the actual commit
/// message/author under a `commit` key and keeps the linked GitHub
/// account (if any) at the top level as `author`; flattened here via a
/// custom `init` so call sites just see plain properties.
struct ForgeCommit: Decodable, Identifiable, Hashable {
    var sha: String
    var message: String
    var authorName: String
    var authorDate: Date
    var authorLogin: String?
    var authorAvatarURL: String?
    var htmlURL: String

    var id: String { sha }

    private struct Envelope: Decodable {
        var sha: String
        var commit: CommitDetail
        var author: GitHubUserRef?
        var htmlURL: String
        enum CodingKeys: String, CodingKey { case sha, commit, author, htmlURL = "html_url" }
    }
    private struct CommitDetail: Decodable {
        var message: String
        var author: GitAuthor
    }
    private struct GitAuthor: Decodable {
        var name: String
        var date: Date
    }
    private struct GitHubUserRef: Decodable {
        var login: String
        var avatarURL: String
        enum CodingKeys: String, CodingKey { case login, avatarURL = "avatar_url" }
    }

    init(from decoder: Decoder) throws {
        let envelope = try Envelope(from: decoder)
        sha = envelope.sha
        message = envelope.commit.message
        authorName = envelope.commit.author.name
        authorDate = envelope.commit.author.date
        authorLogin = envelope.author?.login
        authorAvatarURL = envelope.author?.avatarURL
        htmlURL = envelope.htmlURL
    }
}

/// One changed file within a commit — `patch` is the unified-diff text
/// straight from GitHub (nil for binary files, or diffs GitHub judged too
/// large to inline).
struct ForgeFileDiff: Decodable, Identifiable, Hashable {
    var filename: String
    var status: String
    var additions: Int
    var deletions: Int
    var patch: String?

    var id: String { filename }
}

/// `GET /repos/{owner}/{repo}/commits/{sha}` — same nested shape as
/// `ForgeCommit` plus the per-file diff list.
struct ForgeCommitDetail: Decodable, Identifiable, Hashable {
    var sha: String
    var message: String
    var authorName: String
    var authorDate: Date
    var authorLogin: String?
    var authorAvatarURL: String?
    var htmlURL: String
    var files: [ForgeFileDiff]

    var id: String { sha }

    private struct Envelope: Decodable {
        var sha: String
        var commit: CommitDetail
        var author: GitHubUserRef?
        var htmlURL: String
        var files: [ForgeFileDiff]
        enum CodingKeys: String, CodingKey { case sha, commit, author, htmlURL = "html_url", files }
    }
    private struct CommitDetail: Decodable {
        var message: String
        var author: GitAuthor
    }
    private struct GitAuthor: Decodable {
        var name: String
        var date: Date
    }
    private struct GitHubUserRef: Decodable {
        var login: String
        var avatarURL: String
        enum CodingKeys: String, CodingKey { case login, avatarURL = "avatar_url" }
    }

    init(from decoder: Decoder) throws {
        let envelope = try Envelope(from: decoder)
        sha = envelope.sha
        message = envelope.commit.message
        authorName = envelope.commit.author.name
        authorDate = envelope.commit.author.date
        authorLogin = envelope.author?.login
        authorAvatarURL = envelope.author?.avatarURL
        htmlURL = envelope.htmlURL
        files = envelope.files
    }
}

/// `GET /repos/{owner}/{repo}/branches`
struct ForgeBranch: Decodable, Identifiable, Hashable {
    var name: String
    var commitSHA: String
    var isProtected: Bool

    var id: String { name }

    private struct CommitRef: Decodable { var sha: String }
    private enum CodingKeys: String, CodingKey { case name, commit, protected }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        commitSHA = try container.decode(CommitRef.self, forKey: .commit).sha
        isProtected = try container.decodeIfPresent(Bool.self, forKey: .protected) ?? false
    }
}

/// `GET/POST .../pulls` — just enough fields to show status and link out;
/// review/merge UI is a later phase. Uses `merged_at` rather than the
/// `merged` boolean GitHub only includes on the single-PR endpoint, not
/// the list endpoint `pullRequest(head:)` reads from.
struct ForgePullRequest: Decodable, Hashable {
    var number: Int
    var title: String
    var state: String
    var mergedAt: Date?
    var htmlURL: String

    var isMerged: Bool { mergedAt != nil }

    enum CodingKeys: String, CodingKey {
        case number, title, state
        case mergedAt = "merged_at"
        case htmlURL = "html_url"
    }
}
