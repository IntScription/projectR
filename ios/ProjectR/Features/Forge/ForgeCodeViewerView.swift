import SwiftUI

/// Plain monospaced source view — no syntax highlighting in Phase 1 (a
/// real highlighter is its own feature). Files over ~1MB hit GitHub's own
/// API cap on inline base64 content, so those show a fallback message
/// rather than pretending to load something that was never coming back.
///
/// Editing is only offered when `branch` is set — reached via a task
/// that already has a branch, never the default branch directly (see
/// `TaskDetailView`'s "Browse files" entry point). Default-branch
/// browsing from the Forge dashboard stays exactly as read-only as it's
/// always been.
struct ForgeCodeViewerView: View {
    let githubURL: String
    let path: String
    let projectID: UUID?
    let branch: String?
    private let provider: GitProvider = GitHubProvider()

    private static let previewSizeLimit = 1_000_000

    @State private var file: ForgeFileContent?
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var isEditing = false
    @State private var editedText = ""
    @State private var isPresentingCommitSheet = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    private var fileName: String { (path as NSString).lastPathComponent }
    private var hasUnsavedChanges: Bool { editedText != (file?.decodedText ?? "") }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn't load this file", systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage))
            } else if let file {
                if file.size > Self.previewSizeLimit {
                    ContentUnavailableView(
                        "Too large to preview", systemImage: "doc.text.magnifyingglass",
                        description: Text("This file is larger than GitHub's inline preview limit."))
                } else if file.decodedText != nil {
                    if isEditing {
                        editor
                    } else {
                        viewer(text: editedText)
                    }
                } else {
                    ContentUnavailableView(
                        "Can't preview this file", systemImage: "doc.questionmark",
                        description: Text("This doesn't look like text."))
                }
            }
        }
        .navigationTitle(fileName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $isPresentingCommitSheet) {
            CommitMessageSheet(defaultMessage: "Update \(fileName)", isSaving: isSaving, errorMessage: saveErrorMessage) {
                message in
                Task { await save(message: message) }
            }
        }
        .task { await load() }
    }

    private func viewer(text: String) -> some View {
        ScrollView(.vertical) {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .textSelection(.enabled)
        }
        .floatingTabBarClearance()
    }

    private var editor: some View {
        TextEditor(text: $editedText)
            .font(.system(.footnote, design: .monospaced))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, 12)
            .floatingTabBarClearance()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    editedText = file?.decodedText ?? ""
                    isEditing = false
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    isPresentingCommitSheet = true
                }
                .disabled(!hasUnsavedChanges)
            }
        } else if let text = file?.decodedText {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Copy code")
            }
            if branch != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isEditing = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Edit file")
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await provider.fileContent(githubURL: githubURL, path: path, ref: branch)
            file = loaded
            editedText = loaded.decodedText ?? ""
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func save(message: String) async {
        // `branch` (and therefore the Edit button itself) is only ever
        // non-nil when reached through a task, which always carries a
        // real project — `projectID` being nil here shouldn't happen in
        // practice, but the activity-post below is skipped rather than
        // crashing if it somehow does.
        guard let file, let branch else { return }
        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }
        do {
            let newSha = try await provider.updateFile(
                githubURL: githubURL, path: path, content: editedText, message: message, sha: file.sha,
                branch: branch)
            self.file = ForgeFileContent(
                name: file.name, path: file.path, size: editedText.utf8.count, encoding: "base64",
                content: Data(editedText.utf8).base64EncodedString(), sha: newSha)
            isEditing = false
            isPresentingCommitSheet = false

            if let projectID {
                try? await SupabaseManager.shared.client
                    .from("project_updates")
                    .insert(
                        NewForgeFileUpdate(
                            projectID: projectID, body: "Updated `\(fileName)` on \(branch)", kind: "file_edited")
                    )
                    .execute()
            }
        } catch {
            saveErrorMessage = ErrorPresentation.message(for: error)
        }
    }
}

/// Same compact one-field-sheet shape as `TasksListView`'s `NewTaskSheet`
/// — a commit needs a message, not a full form. Shared with
/// `ForgeLocalFileEditorView`'s local-clone commit/sync flow.
struct CommitMessageSheet: View {
    let defaultMessage: String
    let isSaving: Bool
    let errorMessage: String?
    var onCommit: (String) -> Void

    @State private var message = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Commit message", text: $message)
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            .navigationTitle("Commit Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Commit") {
                            onCommit(message.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.height(180)])
        .onAppear { message = defaultMessage }
    }
}

private struct NewForgeFileUpdate: Encodable {
    let projectID: UUID
    let body: String
    let kind: String

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case body, kind
    }
}
