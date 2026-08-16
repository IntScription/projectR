import SwiftUI

struct ForgeBranchListView: View {
    let githubURL: String
    let projectID: UUID
    private let provider: GitProvider = GitHubProvider()

    @State private var branches: [ForgeBranch] = []
    @State private var defaultBranch: String?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && branches.isEmpty {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn't load branches", systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage))
            } else if branches.isEmpty {
                ContentUnavailableView("No branches", systemImage: "arrow.triangle.branch")
            } else {
                List(branches) { branch in
                    NavigationLink(
                        value: ForgeDestination.commits(githubURL: githubURL, branch: branch.name, projectID: projectID)
                    ) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(branch.name).font(.subheadline.weight(.medium))
                                    if branch.name == defaultBranch {
                                        Text("default")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                Text(String(branch.commitSHA.prefix(7)))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if branch.isProtected {
                                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .floatingTabBarClearance()
            }
        }
        .navigationTitle("Branches")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let branchesTask = provider.branches(githubURL: githubURL)
            async let repoTask = provider.repoMetadata(githubURL: githubURL)
            branches = try await branchesTask
            defaultBranch = (try? await repoTask)?.defaultBranch
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}
