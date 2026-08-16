import Foundation

/// The seam that keeps Forge from being hard-coded to GitHub — every
/// screen in `Features/Forge` talks to this protocol, not to
/// `GitHubProvider` directly. Only GitHub is implemented for Phase 1; a
/// `GitLabProvider`/`GenericGitProvider` can conform later without any
/// UI code changing, but there's no value in stub types for providers
/// nothing calls yet.
protocol GitProvider: Sendable {
    func repoMetadata(githubURL: String) async throws -> ForgeRepo
    /// `ref` is a branch/tag/sha to read at, or `nil` for the repo's
    /// default branch — lets a task's branch show its own version of a
    /// file instead of always the default branch.
    func contents(githubURL: String, path: String, ref: String?) async throws -> [ForgeTreeEntry]
    func fileContent(githubURL: String, path: String, ref: String?) async throws -> ForgeFileContent
    func commits(githubURL: String, branch: String) async throws -> [ForgeCommit]
    func commitDetail(githubURL: String, sha: String) async throws -> ForgeCommitDetail
    func branches(githubURL: String) async throws -> [ForgeBranch]
    func openPullRequestCount(githubURL: String) async throws -> Int

    /// Creates a new branch pointed at `fromBranch`'s current commit.
    func createBranch(githubURL: String, name: String, fromBranch: String) async throws
    /// Opens a real pull request. `head` is just the branch name (not
    /// `owner:branch` — that qualified form is only needed when the head
    /// branch lives in a fork, which Forge doesn't support creating PRs
    /// from yet).
    func openPullRequest(
        githubURL: String, title: String, head: String, base: String, body: String
    ) async throws -> ForgePullRequest
    /// The most recent PR (any state) for a given head branch, or `nil` if
    /// none exists yet — used to show real PR status instead of just the
    /// dashboard's open-count.
    func pullRequest(githubURL: String, head: String) async throws -> ForgePullRequest?

    /// Commits a single-file edit straight to `branch`. `sha` is the blob
    /// sha the edit started from (`ForgeFileContent.sha`) — GitHub uses it
    /// as an optimistic-concurrency check and rejects the write if the
    /// file changed since. Pass `nil` when the file doesn't exist on
    /// `branch` yet (GitHub creates it rather than requiring a match).
    /// Returns the new blob sha.
    func updateFile(
        githubURL: String, path: String, content: String, message: String, sha: String?, branch: String
    ) async throws -> String

    /// Real, historical, per-week data GitHub itself computes and keeps
    /// refreshed server-side — none of these are approximated or cached by
    /// this app, so "weekly" stays accurate for free every time they're
    /// fetched.
    func commitActivity(githubURL: String) async throws -> [ForgeCommitActivityWeek]
    func codeFrequency(githubURL: String) async throws -> [ForgeCodeFrequencyWeek]
    func contributorStats(githubURL: String) async throws -> [ForgeContributorStat]
    func punchCard(githubURL: String) async throws -> [ForgePunchCardEntry]
    func languageBreakdown(githubURL: String) async throws -> [ForgeLanguageBytes]
    /// Derived client-side from recent issues/PRs — GitHub's REST API
    /// doesn't summarize this itself.
    func issueVelocity(githubURL: String) async throws -> ForgeIssueVelocity
    func pullRequestVelocity(githubURL: String) async throws -> ForgePullRequestVelocity
}

enum GitProviderError: LocalizedError {
    case invalidRepositoryURL
    case requestFailed(status: Int)
    /// GitHub computes `stats/*` endpoints asynchronously the first time
    /// they're requested for a given repo (a `202`, not a failure) — this
    /// is what's left once a short retry still comes back `202`.
    case statsComputing
    /// A `stats/*` endpoint's own hard failure, verbatim from GitHub's
    /// response body — e.g. `code_frequency` genuinely refuses repos with
    /// 10,000+ commits ("repository must have fewer than 10000 commits"),
    /// confirmed against a real large repo. Distinct from `.statsComputing`
    /// since retrying this one never succeeds.
    case statsUnavailable(String)
    /// `updateFile` failed its optimistic-concurrency check — the branch
    /// moved since the `sha` this write started from was read, i.e. a
    /// real conflict, not a generic failure. Carries GitHub's own message
    /// so the UI can show it verbatim.
    case fileConflict(remoteMessage: String)

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryURL: "This doesn't look like a valid repository URL."
        case .requestFailed(let status): "GitHub returned an error (status \(status))."
        case .statsComputing:
            "GitHub is still computing stats for this repository — check back in a moment."
        case .statsUnavailable(let message): message
        case .fileConflict(let remoteMessage): remoteMessage
        }
    }
}
