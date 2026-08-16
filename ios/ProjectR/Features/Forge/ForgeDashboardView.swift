import ForgeCoreKit
import SwiftUI

/// Everything Forge can show for a connected repo, hosted-only metadata
/// plus — now that Phase 2's local git core is real — an actual "Working
/// Tree" section once a repo has been cloned locally: real added/
/// modified/deleted file status computed by `forge-core`'s `gix`-backed
/// engine, not a GitHub API approximation.
struct ForgeDashboardView: View {
    let githubURL: String
    let projectID: UUID
    private let provider: GitProvider = GitHubProvider()

    @State private var repo: ForgeRepo?
    @State private var recentCommits: [ForgeCommit] = []
    @State private var openPullRequestCount: Int?
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var isClonedLocally = false
    @State private var isCloning = false
    @State private var cloneErrorMessage: String?
    @State private var workingTreeStatus: [FileStatus] = []
    @State private var isRefreshingStatus = false

    var body: some View {
        Group {
            if let repo {
                content(for: repo)
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn't load this repository", systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage))
            }
        }
        .task { await load() }
    }

    private func content(for repo: ForgeRepo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                repoCard(for: repo)
                quickLinks(for: repo)
                workingTreeSection
                recentActivity
                engineStatusFooter
            }
            .padding(20)
        }
        .floatingTabBarClearance()
        // Fires again when navigating back from `ForgeLocalFileEditorView`
        // (this view isn't recreated, just re-shown), which is the one
        // moment the on-disk working tree can have changed underneath it —
        // `.task` alone only ever runs once per view identity.
        .onAppear {
            if isClonedLocally {
                Task { await refreshWorkingTreeStatus() }
            }
        }
    }

    /// Real local working-tree state once this repo has been cloned via
    /// `forge-core`'s `gix` engine — not a GitHub API approximation, an
    /// actual HEAD-tree-vs-working-directory comparison computed on disk.
    @ViewBuilder
    private var workingTreeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Working Tree").font(.headline)
            if isClonedLocally {
                clonedWorkingTreeCard
            } else {
                cloneCard
            }
        }
    }

    private var cloneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clone this repo locally to see real working-tree status, edit files offline, and commit before syncing back to GitHub.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let cloneErrorMessage {
                Text(cloneErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button {
                Task { await cloneLocally() }
            } label: {
                HStack {
                    if isCloning {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                    }
                    Text(isCloning ? "Cloning…" : "Clone locally")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCloning)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var clonedWorkingTreeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(workingTreeStatus.isEmpty ? "No changes" : "\(workingTreeStatus.count) changed file\(workingTreeStatus.count == 1 ? "" : "s")")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if isRefreshingStatus {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await refreshWorkingTreeStatus() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)

            if !workingTreeStatus.isEmpty {
                Divider().padding(.horizontal, 16)
                ForEach(Array(workingTreeStatus.enumerated()), id: \.offset) { index, status in
                    NavigationLink(
                        value: ForgeLocalFileRoute(githubURL: githubURL, path: status.path, projectID: projectID)
                    ) {
                        HStack(spacing: 10) {
                            changeKindIcon(status.change)
                            Text(status.path)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    if index < workingTreeStatus.count - 1 {
                        Divider().padding(.leading, 42)
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func changeKindIcon(_ change: ChangeKind) -> some View {
        let (systemImage, color): (String, Color) = {
            switch change {
            case .added: ("plus.circle.fill", .green)
            case .modified: ("pencil.circle.fill", .orange)
            case .deleted: ("minus.circle.fill", .red)
            }
        }()
        return Image(systemName: systemImage).foregroundStyle(color)
    }

    private func repoCard(for repo: ForgeRepo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(repo.fullName).font(.title3.bold())
            if let description = repo.description, !description.isEmpty {
                Text(description).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                Label(repo.defaultBranch, systemImage: "arrow.triangle.branch")
                Label("\(repo.starCount)", systemImage: "star")
                Label("\(repo.openIssuesCount)", systemImage: "exclamationmark.circle")
                if let openPullRequestCount {
                    Label("\(openPullRequestCount)", systemImage: "arrow.triangle.pull")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func quickLinks(for repo: ForgeRepo) -> some View {
        HStack(spacing: 12) {
            NavigationLink(value: ForgeDestination.files(githubURL: githubURL, path: "", projectID: projectID)) {
                quickLinkTile("Files", systemImage: "folder.fill")
            }
            NavigationLink(
                value: ForgeDestination.commits(githubURL: githubURL, branch: repo.defaultBranch, projectID: projectID)
            ) {
                quickLinkTile("Commits", systemImage: "clock.arrow.circlepath")
            }
            NavigationLink(value: ForgeDestination.branches(githubURL: githubURL, projectID: projectID)) {
                quickLinkTile("Branches", systemImage: "arrow.triangle.branch")
            }
            NavigationLink(value: ForgeDestination.insights(githubURL: githubURL, projectID: projectID)) {
                quickLinkTile("Insights", systemImage: "chart.bar.xaxis")
            }
        }
        .buttonStyle(.plain)
    }

    private func quickLinkTile(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 20)).foregroundStyle(Color.accentColor)
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var recentActivity: some View {
        if !recentCommits.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent Activity").font(.headline)
                ForEach(recentCommits.prefix(5)) { commit in
                    NavigationLink(
                        value: ForgeDestination.commitDetail(githubURL: githubURL, sha: commit.sha, projectID: projectID)
                    ) {
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(.green).frame(width: 6, height: 6).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(commit.message.components(separatedBy: "\n").first ?? commit.message)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(commit.authorName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// A real, visible use of the Rust bridge — not hidden behind a debug
    /// flag or a unit test — proving the seam actually round-trips.
    private var engineStatusFooter: some View {
        Text(engineStatus())
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let repoTask = provider.repoMetadata(githubURL: githubURL)
            let loadedRepo = try await repoTask
            repo = loadedRepo
            async let commitsTask = provider.commits(githubURL: githubURL, branch: loadedRepo.defaultBranch)
            async let pullCountTask = provider.openPullRequestCount(githubURL: githubURL)
            recentCommits = (try? await commitsTask) ?? []
            openPullRequestCount = try? await pullCountTask
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }

        isClonedLocally = LocalRepoManager.isClonedLocally(githubURL: githubURL)
        if isClonedLocally {
            await refreshWorkingTreeStatus()
        }
    }

    private func cloneLocally() async {
        isCloning = true
        cloneErrorMessage = nil
        defer { isCloning = false }
        do {
            guard let token = try await githubToken() else {
                cloneErrorMessage = "Connect GitHub in Settings before cloning a repo."
                return
            }
            try await LocalRepoManager.clone(githubURL: githubURL, token: token)
            isClonedLocally = true
            await refreshWorkingTreeStatus()
        } catch {
            cloneErrorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func refreshWorkingTreeStatus() async {
        isRefreshingStatus = true
        defer { isRefreshingStatus = false }
        workingTreeStatus = (try? await LocalRepoManager.status(githubURL: githubURL)) ?? []
    }

    private func githubToken() async throws -> String? {
        try await SupabaseManager.shared.client.rpc("get_my_github_access_token").execute().value
    }
}

/// Reached from a "Working Tree" row — a file that's changed in a locally
/// cloned repo, edited/committed/synced through `LocalRepoManager` rather
/// than the REST-only `ForgeCodeViewerView`. `projectID` is nil for repos
/// cloned without a ProjectR project attached, same reasoning as
/// `ForgeDestination`.
struct ForgeLocalFileRoute: Hashable {
    let githubURL: String
    let path: String
    let projectID: UUID?
}

/// Every screen Forge can push to from the dashboard, in one enum so a
/// single `.navigationDestination(for:)` (on `ProjectDetailView`, the
/// common ancestor of both the Forge and Tasks branches) covers all of
/// them instead of one modifier per destination type. The commit-related
/// cases carry `projectID` so those screens can look up this project's
/// tasks for `#N` commit-message linking without a second navigation
/// value type.
enum ForgeDestination: Hashable {
    /// `branch` is nil for read-only default-branch browsing (the usual
    /// case, reached from the dashboard's "Files" link) or a task's
    /// branch name when reached from `TaskDetailView` — only the latter
    /// offers editing, in `ForgeCodeViewerView`. `projectID` is nil when
    /// browsing a repo straight from `ForgeRepositoriesView` that isn't
    /// attached to any ProjectR project yet — there's no project to link
    /// tasks/activity to, which is fine since editing (the only place
    /// that actually needs it) is already gated on `branch != nil`.
    case files(githubURL: String, path: String, projectID: UUID?, branch: String? = nil)
    case file(githubURL: String, path: String, projectID: UUID?, branch: String? = nil)
    case commits(githubURL: String, branch: String, projectID: UUID)
    case commitDetail(githubURL: String, sha: String, projectID: UUID)
    case branches(githubURL: String, projectID: UUID)
    /// Strengths/weaknesses + real GitHub-derived graphs for a repo.
    /// `projectID` nil for repos browsed straight from
    /// `ForgeRepositoriesView` — same reasoning as `.files`/`.file`, and
    /// it additionally gates the star-growth trend chart, which only
    /// makes sense for repos actually attached to a project.
    case insights(githubURL: String, projectID: UUID?)
}
