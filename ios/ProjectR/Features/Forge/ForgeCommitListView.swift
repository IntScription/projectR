import SwiftUI

struct ForgeCommitListView: View {
    let githubURL: String
    let branch: String
    let projectID: UUID
    private let provider: GitProvider = GitHubProvider()

    @State private var commits: [ForgeCommit] = []
    @State private var tasks: [ProjectTask] = []
    @State private var project: Project?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && commits.isEmpty {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn't load commits", systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage))
            } else if commits.isEmpty {
                ContentUnavailableView("No commits", systemImage: "clock.arrow.circlepath")
            } else {
                List(commits) { commit in
                    NavigationLink(
                        value: ForgeDestination.commitDetail(githubURL: githubURL, sha: commit.sha, projectID: projectID)
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(commit.message.components(separatedBy: "\n").first ?? commit.message)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                            HStack(spacing: 6) {
                                Text(commit.authorName)
                                Text("·")
                                Text(commit.authorDate, format: .dateTime.month(.abbreviated).day())
                                Text("·")
                                Text(String(commit.sha.prefix(7))).font(.system(.caption, design: .monospaced))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if let project, let task = TaskLinking.referencedTask(in: commit.message, tasks: tasks) {
                                TaskChip(task: task, project: project)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .floatingTabBarClearance()
            }
        }
        .navigationTitle(branch)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let commitsTask = provider.commits(githubURL: githubURL, branch: branch)
            async let tasksTask: [ProjectTask] =
                SupabaseManager.shared.client
                .from("tasks").select().eq("project_id", value: projectID).execute().value
            async let projectTask: Project =
                SupabaseManager.shared.client
                .from("projects").select().eq("id", value: projectID).single().execute().value
            commits = try await commitsTask
            tasks = (try? await tasksTask) ?? []
            project = try? await projectTask
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}
