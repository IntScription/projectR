import SwiftUI

/// Editor for a file inside a locally cloned repo (`LocalRepoManager`,
/// backed by `forge-core`'s real `gix` engine) — reached from
/// `ForgeDashboardView`'s Working Tree list, not the REST-only
/// `ForgeFileBrowserView`/`ForgeCodeViewerView` pair. Reads/writes hit the
/// on-disk clone directly, with no network round-trip, until "Sync":
/// that stages + commits locally (a real commit object, via `gix`), then
/// pushes the result to GitHub through the existing, already-proven REST
/// `GitProvider.updateFile` path — not `gix`'s own push, which isn't
/// reliable yet (see the Forge Phase 2 plan for why).
struct ForgeLocalFileEditorView: View {
    let githubURL: String
    let path: String
    let projectID: UUID?
    private let provider: GitProvider = GitHubProvider()

    private var fileName: String { (path as NSString).lastPathComponent }

    @State private var originalText = ""
    @State private var editedText = ""
    @State private var diffText = ""
    @State private var defaultBranch = "main"
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var isShowingDiff = false
    @State private var isPresentingSyncSheet = false
    @State private var isSyncing = false
    @State private var syncErrorMessage: String?
    @State private var didSync = false

    // A real conflict (the branch moved since the sync started) rather
    // than a generic failure — offers an actual resolution instead of
    // just showing GitHub's error text.
    @State private var isPresentingConflict = false
    @State private var conflictRemoteMessage = ""
    @State private var pendingSyncMessage = ""
    @State private var isPresentingRemoteContent = false
    @State private var remoteContent = ""
    @State private var isLoadingRemoteContent = false

    private var hasLocalEdits: Bool { editedText != originalText }
    /// `hasLocalEdits` alone isn't the right signal for whether there's
    /// anything to sync — a file reached from the Working Tree list can
    /// already differ from HEAD before a single keystroke happens here,
    /// and after a successful sync `diffText` goes back to empty. Without
    /// this, tapping "Sync" a second time with nothing new committed a
    /// real empty commit and pushed it — confirmed as a real bug, not
    /// hypothetical.
    private var hasChangesToSync: Bool { hasLocalEdits || !diffText.isEmpty }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn't load this file", systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage))
            } else if isShowingDiff {
                diffView
            } else {
                editor
            }
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $isPresentingSyncSheet) {
            CommitMessageSheet(
                defaultMessage: "Update \(fileName)", isSaving: isSyncing, errorMessage: syncErrorMessage
            ) { message in
                Task { await sync(message: message) }
            }
        }
        .copyToast("Synced to GitHub", isPresented: $didSync)
        .confirmationDialog(
            "This file changed on GitHub since you started editing", isPresented: $isPresentingConflict,
            titleVisibility: .visible
        ) {
            Button("Overwrite with my version") { Task { await overwriteRemote() } }
            Button("View latest from GitHub") { Task { await loadRemoteContent() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(conflictRemoteMessage)
        }
        .sheet(isPresented: $isPresentingRemoteContent) {
            NavigationStack {
                Group {
                    if isLoadingRemoteContent {
                        ProgressView()
                    } else {
                        ScrollView {
                            Text(remoteContent)
                                .font(.system(.footnote, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .textSelection(.enabled)
                        }
                    }
                }
                .navigationTitle("Latest on GitHub")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { isPresentingRemoteContent = false }
                    }
                }
            }
        }
        .task { await load() }
    }

    private var editor: some View {
        TextEditor(text: $editedText)
            .font(.system(.footnote, design: .monospaced))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 12)
            .floatingTabBarClearance()
    }

    private var diffView: some View {
        ScrollView(.vertical) {
            Text(diffText.isEmpty ? "No changes against HEAD." : diffText)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .textSelection(.enabled)
        }
        .floatingTabBarClearance()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isShowingDiff.toggle()
            } label: {
                Image(systemName: isShowingDiff ? "pencil" : "plusminus")
            }
            .accessibilityLabel(isShowingDiff ? "Edit file" : "View diff")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await saveLocally() }
            } label: {
                Image(systemName: "arrow.down.doc")
            }
            .accessibilityLabel("Save to local clone")
            .disabled(!hasLocalEdits)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Sync") {
                isPresentingSyncSheet = true
            }
            .disabled(!hasChangesToSync)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let contentTask = LocalRepoManager.readFile(githubURL: githubURL, path: path)
            async let diffTask = LocalRepoManager.diff(githubURL: githubURL, path: path)
            async let repoTask = provider.repoMetadata(githubURL: githubURL)
            let content = try await contentTask
            originalText = content
            editedText = content
            diffText = (try? await diffTask) ?? ""
            defaultBranch = (try? await repoTask)?.defaultBranch ?? defaultBranch
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func saveLocally() async {
        guard hasLocalEdits else { return }
        do {
            try await LocalRepoManager.writeFile(githubURL: githubURL, path: path, content: editedText)
            originalText = editedText
            diffText = (try? await LocalRepoManager.diff(githubURL: githubURL, path: path)) ?? diffText
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func sync(message: String) async {
        isSyncing = true
        syncErrorMessage = nil
        defer { isSyncing = false }
        do {
            try await commitLocallyIfNeeded(message: message)
            try await pushToRemote(message: message)
            await finishSync(projectID: projectID)
        } catch let error as GitProviderError {
            if case .fileConflict(let remoteMessage) = error {
                // The local commit above already landed — only the push
                // failed, so retrying just needs to redo the push half
                // (`overwriteRemote`), not re-commit the same content
                // again.
                pendingSyncMessage = message
                conflictRemoteMessage = remoteMessage
                isPresentingSyncSheet = false
                isPresentingConflict = true
            } else {
                CrashReporter.capture(error, context: "forge_sync")
                syncErrorMessage = ErrorPresentation.message(for: error)
            }
        } catch {
            CrashReporter.capture(error, context: "forge_sync")
            syncErrorMessage = ErrorPresentation.message(for: error)
        }
    }

    /// The explicit "I know it moved, push my version anyway" resolution
    /// — re-reads whatever the *current* remote sha is right before
    /// pushing (deliberately, even though that's the exact value that
    /// just changed), since choosing to overwrite means push regardless
    /// of what's actually there.
    private func overwriteRemote() async {
        isSyncing = true
        syncErrorMessage = nil
        defer { isSyncing = false }
        do {
            try await pushToRemote(message: pendingSyncMessage)
            await finishSync(projectID: projectID)
        } catch {
            syncErrorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func loadRemoteContent() async {
        isLoadingRemoteContent = true
        isPresentingRemoteContent = true
        defer { isLoadingRemoteContent = false }
        let file = try? await provider.fileContent(githubURL: githubURL, path: path, ref: defaultBranch)
        remoteContent = file?.decodedText ?? "Couldn't load the latest version."
    }

    private func commitLocallyIfNeeded(message: String) async throws {
        if hasLocalEdits {
            try await LocalRepoManager.writeFile(githubURL: githubURL, path: path, content: editedText)
            originalText = editedText
        }
        let (authorName, authorEmail) = await currentAuthor()
        try await LocalRepoManager.commit(
            githubURL: githubURL, paths: [path], message: message, authorName: authorName,
            authorEmail: authorEmail)
    }

    private func pushToRemote(message: String) async throws {
        // The remote blob sha this file currently has on its default
        // branch, if it exists there at all — nil (rather than a 404
        // surfacing as a hard failure) means this is a new file, which
        // GitHub's contents API creates instead of requiring a match.
        let remoteSha = try? await provider.fileContent(githubURL: githubURL, path: path, ref: defaultBranch).sha
        _ = try await provider.updateFile(
            githubURL: githubURL, path: path, content: editedText, message: message, sha: remoteSha,
            branch: defaultBranch)
    }

    private func finishSync(projectID: UUID?) async {
        diffText = (try? await LocalRepoManager.diff(githubURL: githubURL, path: path)) ?? ""
        isPresentingSyncSheet = false
        didSync = true
        AnalyticsService.track("forge_sync_completed")

        if let projectID {
            try? await SupabaseManager.shared.client
                .from("project_updates")
                .insert(
                    NewForgeLocalFileUpdate(
                        projectID: projectID, body: "Synced `\(fileName)` on \(defaultBranch)",
                        kind: "file_edited")
                )
                .execute()
        }
    }

    private func currentAuthor() async -> (name: String, email: String) {
        let session = SupabaseManager.shared.client.auth.currentSession
        let email = session?.user.email ?? "forge@projectr.app"
        guard let userID = session?.user.id,
            let profile: LocalCommitAuthor = try? await SupabaseManager.shared.client
                .from("profiles")
                .select("display_name")
                .eq("id", value: userID)
                .single()
                .execute()
                .value
        else {
            return (email.components(separatedBy: "@").first ?? "ProjectR User", email)
        }
        return (profile.displayName, email)
    }
}

private struct LocalCommitAuthor: Decodable {
    let displayName: String
    enum CodingKeys: String, CodingKey { case displayName = "display_name" }
}

private struct NewForgeLocalFileUpdate: Encodable {
    let projectID: UUID
    let body: String
    let kind: String

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case body, kind
    }
}
