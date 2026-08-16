import Foundation
import Supabase

/// GitHub has no native iOS SDK, so connecting it is a browser round trip
/// (`linkIdentity` opens Safari; the OAuth app's callback goes to GoTrue,
/// which then redirects to `projectr://auth-callback` — handled in
/// `ProjectRApp.onOpenURL`) rather than the in-app flow Apple/Google get.
///
/// The resulting `session.providerToken` isn't kept around by Supabase
/// past the initial exchange (it doesn't survive the hourly JWT refresh),
/// so it's captured once right after linking instead of being read from
/// the session later.
///
/// The token itself is never written to or read from `github_connections`
/// directly — that table has no client-facing grants at all. Every
/// interaction goes through `security definer` RPCs that store it in
/// Supabase Vault (encrypted at rest) and hard-check `auth.uid()`
/// server-side, so this client never even has the *option* of reading
/// another user's token.
extension Notification.Name {
    /// Posted once, right after a successful connect/disconnect — the
    /// single choke point (`connectAndWait()`/`disconnect()`) both go
    /// through regardless of which of the app's several "Connect GitHub"
    /// buttons triggered it, so `RootTabView` can react (reveal the Forge
    /// tab, show its intro) without every call site threading a callback
    /// through.
    static let gitHubDidConnect = Notification.Name("GitHubService.didConnect")
    static let gitHubDidDisconnect = Notification.Name("GitHubService.didDisconnect")
}

enum GitHubService {
    private static let redirectURL = URL(string: "projectr://auth-callback")!

    static func connect() async throws {
        try await SupabaseManager.shared.client.auth.linkIdentity(
            provider: .github,
            scopes: "public_repo",
            redirectTo: redirectURL
        )
    }

    /// Opens GitHub's real login/authorize page directly — no in-app
    /// explainer screen first — then polls until the identity link
    /// actually completes (or times out after a minute). Every "Connect
    /// GitHub" entry point in the app calls this directly from its own
    /// button, rather than presenting a separate confirmation sheet that
    /// only adds a screen between the tap and GitHub's real page.
    static func connectAndWait() async -> Bool {
        do {
            try await connect()
        } catch {
            return false
        }
        for _ in 0..<60 {
            try? await Task.sleep(for: .seconds(1))
            if await isConnected() {
                NotificationCenter.default.post(name: .gitHubDidConnect, object: nil)
                return true
            }
        }
        return false
    }

    /// Called from AuthViewModel's session-change listener whenever a
    /// session carrying a fresh provider token comes through.
    static func captureToken(from session: Session) async {
        guard let token = session.providerToken else { return }

        var username: String?
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: request),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            username = json["login"] as? String
        }

        do {
            try await SupabaseManager.shared.client
                .rpc("set_my_github_access_token", params: SetTokenParams(token: token, username: username))
                .execute()
        } catch {
            // A silent failure here is worse than most — the user believes
            // GitHub is connected (the OAuth round trip itself succeeded)
            // but the token never actually made it into Vault.
            AppLogger.github.error("Failed to store GitHub access token: \(error.localizedDescription)")
        }
    }

    static func isConnected() async -> Bool {
        guard SupabaseManager.shared.client.auth.currentSession != nil else { return false }
        let connected: Bool? =
            try? await SupabaseManager.shared.client
            .rpc("is_my_github_connected")
            .execute()
            .value
        return connected ?? false
    }

    /// Public "GitHub-verified" check for *any* profile — a trust badge,
    /// unlike `isConnected()` which is about the current user's own state
    /// for deciding whether to show the "Connect GitHub" prompt.
    static func isConnected(profileID: UUID) async -> Bool {
        let connected: Bool? =
            try? await SupabaseManager.shared.client
            .rpc("is_github_connected", params: TargetProfileParams(targetProfileID: profileID))
            .execute()
            .value
        return connected ?? false
    }

    static func myUsername() async -> String? {
        try? await SupabaseManager.shared.client
            .rpc("get_my_github_username")
            .execute()
            .value
    }

    static func disconnect() async throws {
        try await SupabaseManager.shared.client
            .rpc("disconnect_my_github")
            .execute()
        NotificationCenter.default.post(name: .gitHubDidDisconnect, object: nil)
    }

    /// Repos the connected account owns, used by "Import from GitHub" when
    /// creating a project — the same token `fork()` uses, just a plain
    /// read instead of a fork.
    static func myRepositories() async throws -> [GitHubRepo] {
        guard
            let token: String =
                try? await SupabaseManager.shared.client
                .rpc("get_my_github_access_token")
                .execute()
                .value
        else {
            throw GitHubServiceError.notConnected
        }

        var request = URLRequest(
            url: URL(string: "https://api.github.com/user/repos?sort=updated&per_page=50")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GitHubServiceError.forkFailed
        }
        return (try? JSONDecoder().decode([GitHubRepo].self, from: data)) ?? []
    }

    static func fork(githubURL: String) async throws -> URL {
        guard let (owner, repo) = parseOwnerRepo(from: githubURL) else {
            throw GitHubServiceError.invalidRepositoryURL
        }

        guard
            let token: String =
                try? await SupabaseManager.shared.client
                .rpc("get_my_github_access_token")
                .execute()
                .value
        else {
            throw GitHubServiceError.notConnected
        }

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(owner)/\(repo)/forks")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GitHubServiceError.forkFailed
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let htmlURLString = json["html_url"] as? String,
            let htmlURL = URL(string: htmlURLString)
        else {
            throw GitHubServiceError.forkFailed
        }
        return htmlURL
    }

    /// Real repo metadata for *any* public GitHub URL, not just the
    /// connected account's own repos — no auth needed, GitHub's repo API
    /// is public for public repos. Used to auto-fill a new project's
    /// description/tech-stack/tags from whatever the user pastes, instead
    /// of asking them to type it all in by hand.
    static func publicMetadata(githubURL: String) async -> GitHubRepo? {
        guard let (owner, repo) = parseOwnerRepo(from: githubURL) else { return nil }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(owner)/\(repo)")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode)
        else {
            return nil
        }
        return try? JSONDecoder().decode(GitHubRepo.self, from: data)
    }

    /// The repo's full language breakdown (bytes per language), not just
    /// the single "primary language" `GitHubRepo.language` carries — a
    /// real project is rarely one language, and tech-stack-driven skill
    /// levels should reflect everything actually used, not just whichever
    /// language happens to have the most bytes. Filtered to languages
    /// contributing at least 5% of the codebase so incidental files (a
    /// stray Dockerfile, a shell script) don't get counted as "skills."
    static func languages(githubURL: String) async -> [String] {
        guard let (owner, repo) = parseOwnerRepo(from: githubURL) else { return [] }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(owner)/\(repo)/languages")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
            let byteCounts = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            return []
        }
        let total = byteCounts.values.reduce(0, +)
        guard total > 0 else { return [] }
        return byteCounts
            .filter { Double($0.value) / Double(total) >= 0.05 }
            .sorted { $0.value > $1.value }
            .map(\.key)
    }

    private static func parseOwnerRepo(from githubURL: String) -> (owner: String, repo: String)? {
        guard let url = URL(string: githubURL) else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 2 else { return nil }
        let repo = components[1].hasSuffix(".git") ? String(components[1].dropLast(4)) : components[1]
        return (components[0], repo)
    }
}

enum GitHubServiceError: LocalizedError {
    case notConnected
    case invalidRepositoryURL
    case forkFailed

    var errorDescription: String? {
        switch self {
        case .notConnected: "Connect your GitHub account first."
        case .invalidRepositoryURL: "This project's GitHub link doesn't look like a valid repository URL."
        case .forkFailed: "Couldn't fork this repository — it may already be forked, or GitHub rejected the request."
        }
    }
}

private struct SetTokenParams: Encodable {
    let token: String
    let username: String?
}

private struct TargetProfileParams: Encodable {
    let targetProfileID: UUID
    enum CodingKeys: String, CodingKey {
        case targetProfileID = "target_profile_id"
    }
}

struct GitHubRepo: Decodable, Identifiable, Hashable {
    var id: Int
    var name: String
    var description: String?
    var htmlURL: String
    var language: String?
    var topics: [String]
    var isPrivate: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case htmlURL = "html_url"
        case language, topics
        case isPrivate = "private"
    }
}
