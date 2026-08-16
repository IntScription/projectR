@preconcurrency import ForgeCoreKit
import Foundation

// UniFFI's generated types don't declare `Sendable` themselves; both are
// plain value types (a string + a string/enum pair) with no reference
// semantics, so this is safe — needed since `status(githubURL:)` returns
// `[FileStatus]` across the `Task.detached` boundary below.
extension FileStatus: @unchecked Sendable {}
extension ChangeKind: @unchecked Sendable {}

/// Swift-side wrapper over the raw UniFFI local-git calls (`ForgeCoreKit`,
/// backed by `forge-core`'s `gix`-based Rust implementation) — decides
/// where local clones live on disk, and turns the synchronous FFI calls
/// into a normal async API so call sites never block the main actor on
/// real file/git I/O.
enum LocalRepoManager {
    /// Application Support, not Documents — clones shouldn't show up in
    /// the Files app or sync to iCloud, and since they're fully
    /// reproducible from GitHub, excluding them from device backups is
    /// correct too, not just an optimization.
    private static var reposRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ForgeRepos", isDirectory: true)
    }

    /// Deterministic per-repo directory from its GitHub URL, so the same
    /// repo always resolves to the same local path across app launches.
    static func localPath(for githubURL: String) -> URL {
        let safe = githubURL
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: "/", with: "_")
        return reposRoot.appendingPathComponent(safe, isDirectory: true)
    }

    static func isClonedLocally(githubURL: String) -> Bool {
        var isDirectory: ObjCBool = false
        let gitDir = localPath(for: githubURL).appendingPathComponent(".git").path
        return FileManager.default.fileExists(atPath: gitDir, isDirectory: &isDirectory)
    }

    static func clone(githubURL: String, token: String) async throws {
        let path = localPath(for: githubURL)
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await Task.detached(priority: .userInitiated) {
            try cloneRepository(url: githubURL, token: token, localPath: path.path, depth: 1)
        }.value
        markExcludedFromBackup(path)
    }

    static func removeLocalClone(githubURL: String) throws {
        let path = localPath(for: githubURL)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }

    static func status(githubURL: String) async throws -> [FileStatus] {
        let path = localPath(for: githubURL).path
        return try await Task.detached(priority: .userInitiated) {
            try workingTreeStatus(localPath: path)
        }.value
    }

    static func diff(githubURL: String, path: String) async throws -> String {
        let localPath = localPath(for: githubURL).path
        return try await Task.detached(priority: .userInitiated) {
            try fileDiff(localPath: localPath, path: path)
        }.value
    }

    static func readFile(githubURL: String, path: String) async throws -> String {
        let localPath = localPath(for: githubURL).path
        return try await Task.detached(priority: .userInitiated) {
            try readWorkingFile(localPath: localPath, path: path)
        }.value
    }

    static func writeFile(githubURL: String, path: String, content: String) async throws {
        let localPath = localPath(for: githubURL).path
        try await Task.detached(priority: .userInitiated) {
            try writeWorkingFile(localPath: localPath, path: path, content: content)
        }.value
    }

    @discardableResult
    static func commit(
        githubURL: String, paths: [String], message: String, authorName: String, authorEmail: String
    ) async throws -> String {
        let localPath = localPath(for: githubURL).path
        return try await Task.detached(priority: .userInitiated) {
            try stageAndCommit(
                localPath: localPath, paths: paths, message: message, authorName: authorName,
                authorEmail: authorEmail)
        }.value
    }

    private static func markExcludedFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}

extension ForgeError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .Network(let message), .Repository(let message), .Io(let message), .Git(let message):
            message
        }
    }
}
