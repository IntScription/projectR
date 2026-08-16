import SwiftUI

/// One directory level of the repo — tapping a folder pushes another
/// instance of this same view at the deeper path (plain `NavigationStack`
/// push navigation, same as the rest of the app), tapping a file pushes
/// `ForgeCodeViewerView`. `path == ""` is the repo root.
struct ForgeFileBrowserView: View {
    let githubURL: String
    let path: String
    let projectID: UUID?
    /// The branch being browsed, or nil for the default branch —
    /// threaded through every recursive folder push so drilling into a
    /// subfolder keeps the same branch context, and into
    /// `ForgeCodeViewerView` so it knows whether to offer editing.
    let branch: String?
    private let provider: GitProvider = GitHubProvider()

    @State private var entries: [ForgeTreeEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var title: String {
        path.isEmpty ? "Files" : (path as NSString).lastPathComponent
    }

    var body: some View {
        Group {
            if isLoading && entries.isEmpty {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn't load this folder", systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage))
            } else if entries.isEmpty {
                ContentUnavailableView("Empty folder", systemImage: "folder")
            } else {
                List(sortedEntries) { entry in
                    NavigationLink(
                        value: entry.isDirectory
                            ? ForgeDestination.files(
                                githubURL: githubURL, path: entry.path, projectID: projectID, branch: branch)
                            : ForgeDestination.file(
                                githubURL: githubURL, path: entry.path, projectID: projectID, branch: branch)
                    ) {
                        Label(entry.name, systemImage: entry.isDirectory ? "folder.fill" : "doc.text")
                            .foregroundStyle(entry.isDirectory ? Color.accentColor : .primary)
                    }
                }
                .listStyle(.plain)
                .floatingTabBarClearance()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    /// Folders before files, then alphabetical within each — matches how
    /// every code host and file browser orders a directory listing.
    private var sortedEntries: [ForgeTreeEntry] {
        entries.sorted {
            $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.name.lowercased() < $1.name.lowercased()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            entries = try await provider.contents(githubURL: githubURL, path: path, ref: branch)
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}
