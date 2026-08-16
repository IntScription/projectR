import SwiftUI

/// The Forge tab's entry point. Forge is inherently project-scoped (it
/// needs a specific repo to browse/commit/branch against), so unlike the
/// other top-level tabs this one is a launcher: pick which of your own
/// projects to open Forge for. Reuses `AddView.loadMyProjects()`'s exact
/// owned+collaborated query shape, since "projects I can act on" is
/// already that same set everywhere else in the app.
///
/// Deliberately skips a big "Forge" page title — a first-time visitor
/// doesn't know what that word means yet, so the intro paragraph does the
/// introducing instead of a heading that would just repeat the tab label
/// they already tapped.
/// Marker route for pushing `ForgeRepositoriesView` — was an inline
/// `NavigationLink { ForgeRepositoriesView() }` destination, which doesn't
/// register in `forgePath` (`RootTabView`'s bound `NavigationPath`) the
/// way every value-based push here does. Mixing the two caused a real
/// desync: opening a repo's files (a value-based push happening *inside*
/// that inline-presented screen) could render against the wrong stack
/// position, showing the repo list again until going back revealed the
/// file browser that had actually been pushed underneath it. Value-based
/// throughout fixes it.
private struct ForgeRepositoriesRoute: Hashable {}

struct ForgeLauncherView: View {
    let profile: Profile

    @State private var myProjects: [Project] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading && myProjects.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        intro
                        repositoriesLink
                        if myProjects.isEmpty {
                            emptyState
                        } else {
                            projectList
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
        }
        .floatingTabBarClearance()
        .navigationBarTitleDisplayMode(.inline)
        // Duplicated from `ProjectDetailView` (this tab's own separate
        // `NavigationStack`, not a descendant of it) — same
        // common-ancestor reasoning: a task pushed from here can lead
        // into a `ForgeDestination`, and a Forge commit can lead into a
        // `TaskRoute`, without ever passing through `ProjectDetailView`.
        .navigationDestination(for: ForgeRepositoriesRoute.self) { _ in
            ForgeRepositoriesView()
        }
        .navigationDestination(for: ForgeRoute.self) { route in
            ForgeLockGateView(project: route.project) { updated in
                if let index = myProjects.firstIndex(where: { $0.id == updated.id }) {
                    myProjects[index] = updated
                }
            }
        }
        .navigationDestination(for: TasksRoute.self) { route in
            TasksListView(project: route.project)
        }
        .navigationDestination(for: TaskRoute.self) { route in
            TaskDetailView(task: route.task, project: route.project)
        }
        .navigationDestination(for: ForgeDestination.self) { destination in
            switch destination {
            case .files(let githubURL, let path, let projectID, let branch):
                ForgeFileBrowserView(githubURL: githubURL, path: path, projectID: projectID, branch: branch)
            case .file(let githubURL, let path, let projectID, let branch):
                ForgeCodeViewerView(githubURL: githubURL, path: path, projectID: projectID, branch: branch)
            case .commits(let githubURL, let branch, let projectID):
                ForgeCommitListView(githubURL: githubURL, branch: branch, projectID: projectID)
            case .commitDetail(let githubURL, let sha, let projectID):
                ForgeCommitDetailView(githubURL: githubURL, sha: sha, projectID: projectID)
            case .branches(let githubURL, let projectID):
                ForgeBranchListView(githubURL: githubURL, projectID: projectID)
            case .insights(let githubURL, let projectID):
                ForgeRepoInsightsView(githubURL: githubURL, projectID: projectID)
            }
        }
        .navigationDestination(for: ForgeLocalFileRoute.self) { route in
            ForgeLocalFileEditorView(githubURL: route.githubURL, path: route.path, projectID: route.projectID)
        }
        .task { await loadMyProjects() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "hammer.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            Text("Your code, in context")
                .font(.title2.weight(.bold))

            Text(
                "Forge connects each project to its GitHub repository — browse files and commits, open pull requests, and turn a task straight into a branch, without leaving ProjectR."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    /// Every repo on the account, not just ones already tied to a
    /// ProjectR project — the point is grabbing a link to paste into
    /// `CreateProjectView`'s GitHub URL field, so this needs to be
    /// reachable before a project (and therefore Forge access to it)
    /// exists yet.
    private var repositoriesLink: some View {
        NavigationLink(value: ForgeRepositoriesRoute()) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Your GitHub repositories")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Copy a link to use when creating a project")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your projects")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 2)

            VStack(spacing: 10) {
                ForEach(myProjects) { project in
                    NavigationLink(value: ForgeRoute(project: project)) {
                        row(for: project)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func row(for project: Project) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "hammer.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(project.githubURL != nil ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 6, height: 6)
                    Text(project.githubURL != nil ? "Repository connected" : "No repository yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No projects yet")
                .font(.headline)
            Text("Create a project first, then open Forge for it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func loadMyProjects() async {
        isLoading = true
        defer { isLoading = false }
        async let ownedTask: [Project] =
            SupabaseManager.shared.client
            .from("projects")
            .select()
            .eq("owner_id", value: profile.id)
            .order("created_at", ascending: false)
            .execute()
            .value
        async let collaboratedTask: [ForgeLauncherCollaboratorEntry] =
            SupabaseManager.shared.client
            .from("project_collaborators")
            .select("project:projects(*)")
            .eq("user_id", value: profile.id)
            .execute()
            .value

        let owned = (try? await ownedTask) ?? []
        let collaborated = (try? await collaboratedTask)?.map(\.project) ?? []
        var seen = Set<UUID>()
        myProjects = (owned + collaborated).filter { seen.insert($0.id).inserted }
    }
}

private struct ForgeLauncherCollaboratorEntry: Decodable {
    let project: Project
}
