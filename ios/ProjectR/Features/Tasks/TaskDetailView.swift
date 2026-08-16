import SwiftUI

/// Branch/PR status and the commits on that branch, sourced through
/// `Core/Forge` exactly like Phase 1's own screens — not a parallel data
/// path. "Create Branch" and "Open PR" are the two real write actions;
/// both record a `project_updates` activity row on success so the action
/// shows up wherever updates already show up (the project page, the
/// profile Posts tab) instead of a second, parallel activity feed.
struct TaskDetailView: View {
    let task: ProjectTask
    let project: Project
    var onUpdated: ((ProjectTask) -> Void)?

    private let provider: GitProvider = GitHubProvider()

    @State private var currentTask: ProjectTask
    @State private var repo: ForgeRepo?
    @State private var commits: [ForgeCommit] = []
    @State private var pullRequest: ForgePullRequest?
    @State private var isLoading = true
    @State private var isCreatingBranch = false
    @State private var isOpeningPR = false
    @State private var errorMessage: String?

    init(task: ProjectTask, project: Project, onUpdated: ((ProjectTask) -> Void)? = nil) {
        self.task = task
        self.project = project
        self.onUpdated = onUpdated
        _currentTask = State(initialValue: task)
    }

    var body: some View {
        Form {
            Section {
                Text(currentTask.title).font(.headline)
                Picker("Status", selection: statusBinding) {
                    ForEach(TaskStatus.allCases) { status in
                        Text(status.label).tag(status)
                    }
                }
            }

            if let branchName = currentTask.branchName {
                Section("Branch") {
                    HStack {
                        Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary)
                        Text(branchName).font(.system(.body, design: .monospaced))
                    }

                    NavigationLink(
                        value: ForgeDestination.files(
                            githubURL: project.githubURL ?? "", path: "", projectID: project.id, branch: branchName)
                    ) {
                        Label("Browse files", systemImage: "folder.fill")
                    }

                    if let pullRequest {
                        Link(destination: URL(string: pullRequest.htmlURL) ?? URL(string: "https://github.com")!) {
                            HStack {
                                Image(systemName: pullRequest.isMerged ? "checkmark.circle.fill" : "arrow.triangle.pull")
                                    .foregroundStyle(pullRequest.isMerged ? .purple : Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("PR #\(pullRequest.number)").font(.subheadline.weight(.medium))
                                    Text(pullRequest.title).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(pullRequest.isMerged ? "Merged" : pullRequest.state.capitalized)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    } else {
                        Button {
                            Task { await openPR() }
                        } label: {
                            if isOpeningPR {
                                ProgressView().frame(maxWidth: .infinity)
                            } else {
                                Text("Open PR").frame(maxWidth: .infinity)
                            }
                        }
                        .disabled(isOpeningPR)
                    }
                }

                if !commits.isEmpty {
                    Section("Commits on this branch") {
                        ForEach(commits) { commit in
                            NavigationLink(
                                value: ForgeDestination.commitDetail(
                                    githubURL: project.githubURL ?? "", sha: commit.sha, projectID: project.id)
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(commit.message.components(separatedBy: "\n").first ?? commit.message)
                                        .lineLimit(1)
                                    Text(commit.authorName).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else {
                Section {
                    Button {
                        Task { await createBranch() }
                    } label: {
                        if isCreatingBranch {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Label("Create Branch", systemImage: "arrow.triangle.branch")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isCreatingBranch || project.githubURL == nil)
                } footer: {
                    if project.githubURL == nil {
                        Text("Connect a repository in Forge first.")
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .floatingTabBarClearance()
        .navigationTitle("#\(currentTask.number)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var statusBinding: Binding<TaskStatus> {
        Binding(
            get: { currentTask.status },
            set: { newValue in
                currentTask.status = newValue
                Task { await updateStatus(newValue) }
            })
    }

    private func load() async {
        guard let githubURL = project.githubURL else {
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        repo = try? await provider.repoMetadata(githubURL: githubURL)
        if let branchName = currentTask.branchName {
            async let commitsTask = provider.commits(githubURL: githubURL, branch: branchName)
            async let pullRequestTask = provider.pullRequest(githubURL: githubURL, head: branchName)
            commits = (try? await commitsTask) ?? []
            pullRequest = try? await pullRequestTask
        }
    }

    private func updateStatus(_ status: TaskStatus) async {
        try? await SupabaseManager.shared.client
            .from("tasks")
            .update(["status": status.rawValue])
            .eq("id", value: currentTask.id)
            .execute()
        onUpdated?(currentTask)
    }

    private func createBranch() async {
        guard let githubURL = project.githubURL, let repo else { return }
        isCreatingBranch = true
        errorMessage = nil
        defer { isCreatingBranch = false }
        do {
            let branchName = "feature/\(currentTask.number)-\(Self.slugify(currentTask.title))"
            try await provider.createBranch(githubURL: githubURL, name: branchName, fromBranch: repo.defaultBranch)

            let updated: ProjectTask =
                try await SupabaseManager.shared.client
                .from("tasks")
                .update(["branch_name": branchName])
                .eq("id", value: currentTask.id)
                .select()
                .single()
                .execute()
                .value
            currentTask = updated
            onUpdated?(updated)

            try? await SupabaseManager.shared.client
                .from("project_updates")
                .insert(
                    NewForgeUpdate(
                        projectID: project.id,
                        body: "Created branch `\(branchName)` for #\(currentTask.number) \(currentTask.title)",
                        kind: "branch_created")
                )
                .execute()

            commits = (try? await provider.commits(githubURL: githubURL, branch: branchName)) ?? []
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func openPR() async {
        guard let githubURL = project.githubURL, let repo, let branchName = currentTask.branchName else { return }
        isOpeningPR = true
        errorMessage = nil
        defer { isOpeningPR = false }
        do {
            let pr = try await provider.openPullRequest(
                githubURL: githubURL, title: currentTask.title, head: branchName, base: repo.defaultBranch,
                body: "")
            pullRequest = pr

            try? await SupabaseManager.shared.client
                .from("project_updates")
                .insert(
                    NewForgeUpdate(
                        projectID: project.id, body: "Opened PR #\(pr.number): \(pr.title)", kind: "pr_opened")
                )
                .execute()
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    private static func slugify(_ text: String) -> String {
        let slug =
            text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return String(slug.prefix(40))
    }
}

private struct NewForgeUpdate: Encodable {
    let projectID: UUID
    let body: String
    let kind: String

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case body, kind
    }
}
