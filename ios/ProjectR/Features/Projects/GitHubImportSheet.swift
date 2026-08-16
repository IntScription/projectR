import SwiftUI

/// Lists the connected account's own repos so creating a project can start
/// from real data instead of a blank form — picking one prefills name,
/// description, tech stack (the repo's primary language), tags (its
/// topics), and the GitHub URL itself.
struct GitHubImportSheet: View {
    var onPick: (GitHubRepo) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var repos: [GitHubRepo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't load repos", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else if repos.isEmpty {
                    ContentUnavailableView("No repositories found", systemImage: "shippingbox")
                } else {
                    List(repos) { repo in
                        Button {
                            onPick(repo)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(repo.name).font(.headline)
                                    if repo.isPrivate {
                                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                if let description = repo.description, !description.isEmpty {
                                    Text(description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                if let language = repo.language {
                                    Text(language)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Import from GitHub")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            repos = try await GitHubService.myRepositories()
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}
