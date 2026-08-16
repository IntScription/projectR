import Foundation

/// Talks to `api.github.com` directly — same shape as `GitHubService`:
/// unauthenticated requests work for public repos (proven already by
/// `GitHubService.publicMetadata`/`languages`), and a stored token is
/// attached opportunistically via the same `get_my_github_access_token`
/// RPC whenever the signed-in user has GitHub connected, for whatever
/// that connection's scope currently allows. No new token/Keychain
/// handling needed — Vault-backed storage server-side is already the
/// whole point of that existing design.
struct GitHubProvider: GitProvider {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func repoMetadata(githubURL: String) async throws -> ForgeRepo {
        let (owner, repo) = try parseOwnerRepo(githubURL)
        return try await request("https://api.github.com/repos/\(owner)/\(repo)")
    }

    func contents(githubURL: String, path: String, ref: String?) async throws -> [ForgeTreeEntry] {
        let (owner, repo) = try parseOwnerRepo(githubURL)
        let suffix = path.isEmpty ? "" : "/\(path)"
        let query = ref.map { "?ref=\($0)" } ?? ""
        return try await request("https://api.github.com/repos/\(owner)/\(repo)/contents\(suffix)\(query)")
    }

    func fileContent(githubURL: String, path: String, ref: String?) async throws -> ForgeFileContent {
        let (owner, repo) = try parseOwnerRepo(githubURL)
        let query = ref.map { "?ref=\($0)" } ?? ""
        return try await request("https://api.github.com/repos/\(owner)/\(repo)/contents/\(path)\(query)")
    }

    func commits(githubURL: String, branch: String) async throws -> [ForgeCommit] {
        let (owner, repo) = try parseOwnerRepo(githubURL)
        return try await request(
            "https://api.github.com/repos/\(owner)/\(repo)/commits?sha=\(branch)&per_page=30")
    }

    func commitDetail(githubURL: String, sha: String) async throws -> ForgeCommitDetail {
        let (owner, repo) = try parseOwnerRepo(githubURL)
        return try await request("https://api.github.com/repos/\(owner)/\(repo)/commits/\(sha)")
    }

    func branches(githubURL: String) async throws -> [ForgeBranch] {
        let (owner, repo) = try parseOwnerRepo(githubURL)
        return try await request("https://api.github.com/repos/\(owner)/\(repo)/branches?per_page=50")
    }

    func openPullRequestCount(githubURL: String) async throws -> Int {
        let (owner, repo) = try parseOwnerRepo(githubURL)
        let url = URL(
            string: "https://api.github.com/repos/\(owner)/\(repo)/pulls?state=open&per_page=1")!
        var urlRequest = await authorizedRequest(url)
        urlRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw GitProviderError.requestFailed(status: 0) }

        // GitHub gives the total count via the `Link` header's pagination
        // rather than a body field — asking for one item per page and
        // reading `rel="last"` avoids fetching every open PR just to
        // count them.
        if let link = http.value(forHTTPHeaderField: "Link"),
            let lastPageString = link.range(of: #"page=(\d+)>; rel="last""#, options: .regularExpression)
        {
            let digits = link[lastPageString].filter(\.isNumber)
            if let count = Int(digits) { return count }
        }
        guard (200...299).contains(http.statusCode) else {
            throw GitProviderError.requestFailed(status: http.statusCode)
        }
        let items = try decoder.decode([EmptyPRItem].self, from: data)
        return items.count
    }

    /// Reads the base branch's current commit sha, then points a new ref
    /// at it — the two real calls behind "create a branch."
    func createBranch(githubURL: String, name: String, fromBranch: String) async throws {
        let (owner, repo) = try parseOwnerRepo(githubURL)
        let baseRef: RefResponse = try await request(
            "https://api.github.com/repos/\(owner)/\(repo)/git/ref/heads/\(fromBranch)")
        let payload = try JSONEncoder().encode(
            CreateRefPayload(ref: "refs/heads/\(name)", sha: baseRef.object.sha))
        let _: RefResponse = try await request(
            "https://api.github.com/repos/\(owner)/\(repo)/git/refs", method: "POST", body: payload)
    }

    func openPullRequest(
        githubURL: String, title: String, head: String, base: String, body: String
    ) async throws -> ForgePullRequest {
        let (owner, repo) = try parseOwnerRepo(githubURL)
        let payload = try JSONEncoder().encode(
            CreatePullRequestPayload(title: title, head: head, base: base, body: body))
        return try await request(
            "https://api.github.com/repos/\(owner)/\(repo)/pulls", method: "POST", body: payload)
    }

    func pullRequest(githubURL: String, head: String) async throws -> ForgePullRequest? {
        let (owner, repo) = try parseOwnerRepo(githubURL)
        let items: [ForgePullRequest] = try await request(
            "https://api.github.com/repos/\(owner)/\(repo)/pulls?head=\(owner):\(head)&state=all&per_page=1"
        )
        return items.first
    }

    func updateFile(
        githubURL: String, path: String, content: String, message: String, sha: String?, branch: String
    ) async throws -> String {
        let (owner, repo) = try parseOwnerRepo(githubURL)
        let payload = try JSONEncoder().encode(
            UpdateFilePayload(
                message: message, content: Data(content.utf8).base64EncodedString(), sha: sha, branch: branch))
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/contents/\(path)")!
        var urlRequest = await authorizedRequest(url)
        urlRequest.httpMethod = "PUT"
        urlRequest.httpBody = payload
        urlRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw GitProviderError.requestFailed(status: 0) }
        // 409 is specifically GitHub's "the sha you sent doesn't match the
        // file's current sha" — the real, narrow conflict window between
        // reading `sha` and this write landing (someone else pushed in
        // between). Every other non-2xx is a generic failure.
        if http.statusCode == 409 {
            let message =
                (try? decoder.decode(GitHubErrorBody.self, from: data))?.message
                ?? "This file changed on GitHub since you started editing."
            throw GitProviderError.fileConflict(remoteMessage: message)
        }
        guard (200...299).contains(http.statusCode) else {
            throw GitProviderError.requestFailed(status: http.statusCode)
        }
        return try decoder.decode(UpdateFileResponse.self, from: data).content.sha
    }

    func commitActivity(githubURL: String) async throws -> [ForgeCommitActivityWeek] {
        let (owner, repo) = try parseOwnerRepo(githubURL)
        return try await statsRequest("https://api.github.com/repos/\(owner)/\(repo)/stats/commit_activity")
    }

    func codeFrequency(githubURL: String) async throws -> [ForgeCodeFrequencyWeek] {
        let (owner, repo) = try parseOwnerRepo(githubURL)
        return try await statsRequest("https://api.github.com/repos/\(owner)/\(repo)/stats/code_frequency")
    }

    func contributorStats(githubURL: String) async throws -> [ForgeContributorStat] {
        let (owner, repo) = try parseOwnerRepo(githubURL)
        let stats: [ForgeContributorStat] = try await statsRequest(
            "https://api.github.com/repos/\(owner)/\(repo)/stats/contributors")
        return stats.sorted { $0.total > $1.total }
    }

    func punchCard(githubURL: String) async throws -> [ForgePunchCardEntry] {
        let (owner, repo) = try parseOwnerRepo(githubURL)
        return try await statsRequest("https://api.github.com/repos/\(owner)/\(repo)/stats/punch_card")
    }

    func languageBreakdown(githubURL: String) async throws -> [ForgeLanguageBytes] {
        let (owner, repo) = try parseOwnerRepo(githubURL)
        let byteCounts: [String: Int] = try await request(
            "https://api.github.com/repos/\(owner)/\(repo)/languages")
        return byteCounts.map { ForgeLanguageBytes(language: $0.key, bytes: $0.value) }
            .sorted { $0.bytes > $1.bytes }
    }

    func issueVelocity(githubURL: String) async throws -> ForgeIssueVelocity {
        let (owner, repo) = try parseOwnerRepo(githubURL)
        let entries: [IssueEntry] = try await request(
            "https://api.github.com/repos/\(owner)/\(repo)/issues?state=all&per_page=100")
        // GitHub's issues endpoint includes pull requests (a PR *is* an
        // issue internally) — `pull_request` is only present on those, so
        // its absence is what actually means "this is a real issue."
        let issuesOnly = entries.filter { $0.pullRequest == nil }
        let open = issuesOnly.filter { $0.state == "open" }.count
        let closed = issuesOnly.filter { $0.state == "closed" }
        let daysToClose = closed.compactMap { issue -> Double? in
            guard let closedAt = issue.closedAt else { return nil }
            return closedAt.timeIntervalSince(issue.createdAt) / 86400
        }
        return ForgeIssueVelocity(
            openCount: open, closedCount: closed.count,
            averageDaysToClose: daysToClose.isEmpty ? nil : daysToClose.reduce(0, +) / Double(daysToClose.count))
    }

    func pullRequestVelocity(githubURL: String) async throws -> ForgePullRequestVelocity {
        let (owner, repo) = try parseOwnerRepo(githubURL)
        let entries: [PullEntry] = try await request(
            "https://api.github.com/repos/\(owner)/\(repo)/pulls?state=all&per_page=100")
        let open = entries.filter { $0.state == "open" }.count
        let merged = entries.filter { $0.mergedAt != nil }
        let closedWithoutMerge = entries.filter { $0.state == "closed" && $0.mergedAt == nil }.count
        let daysToMerge = merged.compactMap { pr -> Double? in
            guard let mergedAt = pr.mergedAt else { return nil }
            return mergedAt.timeIntervalSince(pr.createdAt) / 86400
        }
        let totalClosed = merged.count + closedWithoutMerge
        return ForgePullRequestVelocity(
            openCount: open, mergedCount: merged.count, closedWithoutMergeCount: closedWithoutMerge,
            averageDaysToMerge: daysToMerge.isEmpty ? nil : daysToMerge.reduce(0, +) / Double(daysToMerge.count),
            mergeRate: totalClosed == 0 ? nil : Double(merged.count) / Double(totalClosed))
    }

    private struct IssueEntry: Decodable {
        var state: String
        var createdAt: Date
        var closedAt: Date?
        var pullRequest: PullRequestMarker?
        struct PullRequestMarker: Decodable {}
        enum CodingKeys: String, CodingKey {
            case state, createdAt = "created_at", closedAt = "closed_at", pullRequest = "pull_request"
        }
    }

    private struct PullEntry: Decodable {
        var state: String
        var createdAt: Date
        var mergedAt: Date?
        enum CodingKeys: String, CodingKey {
            case state, createdAt = "created_at", mergedAt = "merged_at"
        }
    }

    private struct EmptyPRItem: Decodable {}

    /// `sha` is omitted from the encoded payload (not sent as `null`) when
    /// nil — GitHub's contents API treats a present `sha` as "update this
    /// existing blob" and its absence as "create a new file"; sending an
    /// explicit null is not the same thing to that API.
    private struct UpdateFilePayload: Encodable {
        let message: String
        let content: String
        let sha: String?
        let branch: String

        enum CodingKeys: String, CodingKey { case message, content, sha, branch }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(message, forKey: .message)
            try container.encode(content, forKey: .content)
            try container.encodeIfPresent(sha, forKey: .sha)
            try container.encode(branch, forKey: .branch)
        }
    }

    private struct UpdateFileResponse: Decodable {
        let content: ContentRef
        struct ContentRef: Decodable { let sha: String }
    }

    private struct RefResponse: Decodable {
        struct ObjectRef: Decodable { let sha: String }
        let object: ObjectRef
    }

    private struct CreateRefPayload: Encodable {
        let ref: String
        let sha: String
    }

    private struct CreatePullRequestPayload: Encodable {
        let title: String
        let head: String
        let base: String
        let body: String
    }

    private func request<T: Decodable>(
        _ urlString: String, method: String = "GET", body: Data? = nil
    ) async throws -> T {
        guard let url = URL(string: urlString) else { throw GitProviderError.invalidRepositoryURL }
        var urlRequest = await authorizedRequest(url)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if let body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw GitProviderError.requestFailed(status: status)
        }
        return try decoder.decode(T.self, from: data)
    }

    /// Same shape as `request`, but for GitHub's `stats/*` endpoints,
    /// which compute their result asynchronously the first time anyone
    /// asks for a given repo — a `202` means "still computing," not a
    /// failure, so this retries once after a short delay before giving up
    /// with `.statsComputing` rather than a misleading generic error.
    private func statsRequest<T: Decodable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw GitProviderError.invalidRepositoryURL }
        for attempt in 0..<2 {
            var urlRequest = await authorizedRequest(url)
            urlRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw GitProviderError.requestFailed(status: 0) }
            if http.statusCode == 202 {
                if attempt == 0 {
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }
                throw GitProviderError.statsComputing
            }
            guard (200...299).contains(http.statusCode) else {
                if let body = try? decoder.decode(GitHubErrorBody.self, from: data), let message = body.message {
                    throw GitProviderError.statsUnavailable(message)
                }
                throw GitProviderError.requestFailed(status: http.statusCode)
            }
            return try decoder.decode(T.self, from: data)
        }
        throw GitProviderError.statsComputing
    }

    private struct GitHubErrorBody: Decodable { let message: String? }

    private func authorizedRequest(_ url: URL) async -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        if let token: String =
            try? await SupabaseManager.shared.client.rpc("get_my_github_access_token").execute().value
        {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func parseOwnerRepo(_ githubURL: String) throws -> (owner: String, repo: String) {
        guard let url = URL(string: githubURL) else { throw GitProviderError.invalidRepositoryURL }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2 else { throw GitProviderError.invalidRepositoryURL }
        let repo = components[1].hasSuffix(".git") ? String(components[1].dropLast(4)) : components[1]
        return (components[0], repo)
    }
}
