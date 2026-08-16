import SwiftUI
import UIKit

/// Navigation value for pushing Forge from this project's own toolbar —
/// carries the whole `Project` (already `Hashable`) rather than just an
/// id, since `ForgeView` needs the current `githubURL` and owner id
/// without a redundant re-fetch.
struct ForgeRoute: Hashable {
    let project: Project
}

/// Same purpose as `ForgeRoute`, for the Tasks entry point.
struct TasksRoute: Hashable {
    let project: Project
}

struct ProjectDetailView: View {
    let projectID: UUID

    @Environment(\.dismiss) private var dismiss

    @State private var project: Project?
    @State private var owner: Profile?
    @State private var media: [ProjectMediaItem] = []
    @State private var updates: [ProjectUpdate] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isPresentingPostUpdate = false
    @State private var isDownloading = false
    @State private var downloadErrorMessage: String?
    @State private var isCollaborator = false
    @State private var isPresentingEdit = false
    @State private var isPresentingReport = false
    @State private var isPresentingDeleteConfirm = false
    @State private var isDeletingProject = false
    @State private var deleteErrorMessage: String?
    @State private var updatePendingDeleteID: UUID?
    @State private var didDelete = false

    private var isOwner: Bool {
        guard let project else { return false }
        return project.ownerID == SupabaseManager.shared.client.auth.currentSession?.user.id
    }

    private var canPostUpdate: Bool { isOwner || isCollaborator }

    var body: some View {
        ScrollView {
            if let project {
                VStack(alignment: .leading, spacing: 0) {
                    coverBanner(for: project)
                    VStack(alignment: .leading, spacing: 20) {
                        header(for: project)
                        engagementRow(for: project)
                        linksSection(for: project)
                        CollaboratorsSection(projectID: project.id, isOwner: isOwner)
                        if !media.isEmpty {
                            mediaGrid
                        }
                        updatesSection
                    }
                    .padding(24)
                }
            } else if isLoading {
                ProgressView().padding(.top, 80)
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding()
            }
        }
        .refreshable { await load() }
        .floatingTabBarClearance()
        .navigationTitle(project?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let project {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: ShareLinks.project(slug: project.slug))
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: ForgeRoute(project: project)) {
                        Image(systemName: "hammer.fill")
                    }
                    .accessibilityLabel("Forge")
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(value: TasksRoute(project: project)) {
                        Image(systemName: "checklist")
                    }
                    .accessibilityLabel("Tasks")
                }
            }
            if canPostUpdate {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingPostUpdate = true
                    } label: {
                        Image(systemName: "plus.bubble")
                    }
                    .accessibilityLabel("Post an update")
                }
            }
            if isOwner {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isPresentingEdit = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            isPresentingDeleteConfirm = true
                        } label: {
                            Label("Delete Project", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Project options")
                }
            } else if project != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingReport = true
                    } label: {
                        Image(systemName: "flag")
                    }
                    .accessibilityLabel("Report project")
                }
            }
        }
        .navigationDestination(for: ForgeRoute.self) { route in
            ForgeLockGateView(project: route.project) { updated in
                project = updated
            }
        }
        .navigationDestination(for: TasksRoute.self) { route in
            TasksListView(project: route.project)
        }
        // Also registered here rather than on `TasksListView` — a `TaskChip`
        // tapped from a Forge commit view needs this to work even when the
        // user reached that commit without ever opening the Tasks list.
        .navigationDestination(for: TaskRoute.self) { route in
            TaskDetailView(task: route.task, project: route.project)
        }
        // Registered here (the common ancestor of both the Forge and
        // Tasks branches) rather than on `ForgeView` itself, since a task
        // detail screen can push straight into a `ForgeDestination` (e.g.
        // a commit it references) without the user ever having opened
        // Forge directly in that navigation path.
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
        .sheet(isPresented: $isPresentingReport) {
            if let project {
                ReportSheet(targetType: .project, targetID: project.id)
            }
        }
        .sheet(isPresented: $isPresentingPostUpdate) {
            if let project, let uploaderID = SupabaseManager.shared.client.auth.currentSession?.user.id {
                PostUpdateView(projectID: project.id, uploaderID: uploaderID) { created in
                    updates.insert(created, at: 0)
                }
            }
        }
        .sheet(isPresented: $isPresentingEdit) {
            if let project {
                NavigationStack {
                    EditProjectView(project: project) { updated in
                        self.project = updated
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this project?", isPresented: $isPresentingDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await deleteProject() } }
        } message: {
            Text("This permanently deletes the project, its updates, media, and comments. This can't be undone.")
        }
        .alert(
            "Couldn't delete project",
            isPresented: Binding(get: { deleteErrorMessage != nil }, set: { if !$0 { deleteErrorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .confirmationDialog(
            "Delete this update?",
            isPresented: Binding(get: { updatePendingDeleteID != nil }, set: { if !$0 { updatePendingDeleteID = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await deleteUpdate() } }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: didDelete) { _, newValue in newValue }
        .task { await load() }
        .task { await checkCollaboratorStatus() }
    }

    private func deleteProject() async {
        guard let project else { return }
        isDeletingProject = true
        defer { isDeletingProject = false }
        do {
            try await SupabaseManager.shared.client
                .from("projects")
                .delete()
                .eq("id", value: project.id)
                .execute()
            AnalyticsService.track("project_deleted")
            didDelete = true
            dismiss()
        } catch {
            CrashReporter.capture(error, context: "delete_project")
            deleteErrorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func deleteUpdate() async {
        guard let updateID = updatePendingDeleteID else { return }
        updatePendingDeleteID = nil
        do {
            try await SupabaseManager.shared.client
                .from("project_updates")
                .delete()
                .eq("id", value: updateID)
                .execute()
            updates.removeAll { $0.id == updateID }
            didDelete = true
        } catch {
            deleteErrorMessage = ErrorPresentation.message(for: error)
        }
    }

    /// The project's own cover — separate from `mediaGrid` below, which is
    /// per-update media, not the project's own banner. Falls back to the
    /// same gradient-plus-name placeholder the feed cards use, so a
    /// project without a photo still reads as "not broken," just plain.
    @ViewBuilder
    private func coverBanner(for project: Project) -> some View {
        ZStack {
            if let videoURL = project.coverVideoURL.flatMap(URL.init) {
                FeedVideoPlayer(url: videoURL)
            } else if let url = project.coverImageURL.flatMap(URL.init) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    coverPlaceholder(for: project)
                }
            } else {
                coverPlaceholder(for: project)
            }
        }
        .frame(height: 220)
        .clipped()
    }

    private func coverPlaceholder(for project: Project) -> some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.1)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay {
            Text(project.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private func linksSection(for project: Project) -> some View {
        let allLinks: [(label: String, url: String, icon: String)] =
            (project.githubURL.map { [(label: "GitHub", url: $0, icon: "chevron.left.forwardslash.chevron.right")] } ?? [])
            + project.links.map { (label: $0.label, url: $0.url, icon: "link") }

        if !allLinks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(allLinks, id: \.url) { entry in
                    if let url = URL(string: entry.url) {
                        Link(destination: url) {
                            HStack(spacing: 8) {
                                Image(systemName: entry.icon)
                                Text(entry.label)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                            }
                            .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func header(for project: Project) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(project.status.rawValue.capitalized)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.orange.opacity(0.15), in: Capsule())
                Text(project.category.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(project.name).font(.title.bold())
            if let description = project.description {
                Text(description)
            }
            if let owner {
                NavigationLink(value: CreatorRoute(userID: owner.id)) {
                    Text("by \(owner.displayName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            let chips = project.techStack + project.tags
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(chips, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.secondary.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func engagementRow(for project: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                LikeButton(target: .project(project.id))
                CommentButton(target: .project(project.id))
                SaveButton(projectID: project.id)
                Spacer()
                FollowButton(target: .project(project.id))
            }

            if project.isOpenSource, project.githubURL != nil, !isOwner {
                Button {
                    Task { await downloadTapped() }
                } label: {
                    HStack {
                        if isDownloading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.branch")
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Download")
                            Text("Forks to your GitHub")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(isDownloading)

                if let downloadErrorMessage {
                    Text(downloadErrorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
        }
    }

    private func checkCollaboratorStatus() async {
        guard let userID = SupabaseManager.shared.client.auth.currentSession?.user.id else { return }
        isCollaborator =
            (try? await Engagement.exists(
                table: "project_collaborators",
                filters: ["project_id": projectID, "user_id": userID]
            )) ?? false
    }

    private func downloadTapped() async {
        if await GitHubService.isConnected() {
            await performFork()
            return
        }
        isDownloading = true
        let connected = await GitHubService.connectAndWait()
        isDownloading = false
        if connected {
            await performFork()
        } else {
            downloadErrorMessage = "Didn't hear back from GitHub — try again."
        }
    }

    private func performFork() async {
        guard let githubURL = project?.githubURL else { return }
        isDownloading = true
        downloadErrorMessage = nil
        defer { isDownloading = false }
        do {
            let forkURL = try await GitHubService.fork(githubURL: githubURL)
            await UIApplication.shared.open(forkURL)
        } catch {
            downloadErrorMessage = ErrorPresentation.message(for: error)
        }
    }

    private var mediaGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(media) { item in
                    AsyncImage(url: URL(string: item.url)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.secondary.opacity(0.15))
                    }
                    .frame(width: 240, height: 135)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Updates").font(.title3.bold())
            if updates.isEmpty {
                Text("No updates yet.").foregroundStyle(.secondary)
            } else {
                ForEach(updates) { update in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(update.createdAt, format: .dateTime.month(.abbreviated).day())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(update.body)
                            LikeButton(target: .update(update.id))
                                .font(.caption)
                        }
                        if isOwner {
                            Spacer()
                            Button {
                                updatePendingDeleteID = update.id
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete update")
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let client = SupabaseManager.shared.client
            let loadedProject: Project =
                try await client
                .from("projects")
                .select()
                .eq("id", value: projectID)
                .single()
                .execute()
                .value

            async let ownerTask: Profile =
                client
                .from("profiles")
                .select()
                .eq("id", value: loadedProject.ownerID)
                .single()
                .execute()
                .value
            async let mediaTask: [ProjectMediaItem] =
                client
                .from("project_media")
                .select()
                .eq("project_id", value: projectID)
                .order("position")
                .execute()
                .value
            async let updatesTask: [ProjectUpdate] =
                client
                .from("project_updates")
                .select()
                .eq("project_id", value: projectID)
                .order("created_at", ascending: false)
                .execute()
                .value

            project = loadedProject
            owner = try await ownerTask
            media = try await mediaTask
            updates = try await updatesTask
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}

struct ProjectMediaItem: Codable, Identifiable {
    let id: UUID
    var url: String
    var position: Int
}
