import SwiftUI

/// Forge's entry point for a project — branches on whether a repository
/// is connected (`project.githubURL`). Reuses the existing GitHub
/// import flow verbatim (`GitHubImportSheet` — the same component
/// `CreateProjectView` already uses to prefill a new project from a real
/// repo) rather than building a second one.
struct ForgeView: View {
    var onProjectUpdated: ((Project) -> Void)?

    @State private var project: Project
    @State private var isPresentingRepoPicker = false
    @State private var isLinkingRepo = false
    @State private var errorMessage: String?

    private var isOwner: Bool {
        project.ownerID == SupabaseManager.shared.client.auth.currentSession?.user.id
    }

    init(project: Project, onProjectUpdated: ((Project) -> Void)? = nil) {
        self._project = State(initialValue: project)
        self.onProjectUpdated = onProjectUpdated
    }

    var body: some View {
        Group {
            if let githubURL = project.githubURL {
                ForgeDashboardView(githubURL: githubURL, projectID: project.id)
            } else {
                emptyState
            }
        }
        .navigationTitle("Forge")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingRepoPicker) {
            GitHubImportSheet { repo in
                Task { await attachRepo(repo) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 6) {
                Text("Forge").font(.title2.bold())
                Text("Connect a repository to start building.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if isOwner {
                VStack(spacing: 10) {
                    Button {
                        Task { await startConnectFlow() }
                    } label: {
                        if isLinkingRepo {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Connect GitHub").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLinkingRepo)

                    comingSoonRow("Connect GitLab")
                    comingSoonRow("Connect another Git remote")
                }
                .frame(maxWidth: 320)

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }

                Text("Your repository stays connected to this project.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("The project owner hasn't connected a repository yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func comingSoonRow(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("Coming soon").font(.caption).foregroundStyle(.tertiary)
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func startConnectFlow() async {
        if await GitHubService.isConnected() {
            isPresentingRepoPicker = true
            return
        }
        isLinkingRepo = true
        let connected = await GitHubService.connectAndWait()
        isLinkingRepo = false
        if connected {
            isPresentingRepoPicker = true
        } else {
            errorMessage = "Didn't hear back from GitHub — try again."
        }
    }

    private func attachRepo(_ repo: GitHubRepo) async {
        isLinkingRepo = true
        errorMessage = nil
        defer { isLinkingRepo = false }
        do {
            let updated: Project =
                try await SupabaseManager.shared.client
                .from("projects")
                .update(["github_url": repo.htmlURL])
                .eq("id", value: project.id)
                .select()
                .single()
                .execute()
                .value
            project = updated
            onProjectUpdated?(updated)
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}
