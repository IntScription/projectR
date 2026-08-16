import SwiftUI

/// Reached from Settings ("Portfolio" section) and from a quick-action
/// icon on the user's own `ProfileView`. Scores the signed-in user's own
/// projects by real signals (view count, real GitHub stars, tech-stack
/// richness, whether there's real content) and pre-selects the top ones —
/// every project still gets a checkbox, so the score is a starting point,
/// not a lock-in. Selected projects are also freely reorderable (that
/// order becomes the order they appear in the PDF — the score decides a
/// starting point, not the final say on what leads). "Generate PDF"
/// builds the document via `PortfolioPDFGenerator` and shows it in a real
/// preview (`PDFPreviewView`) before anything goes to the share sheet.
struct PortfolioBuilderView: View {
    let profile: Profile
    private let provider: GitProvider = GitHubProvider()

    @State private var scoredProjects: [ScoredProject] = []
    /// Selected project IDs, in the order they'll appear in the PDF —
    /// membership *and* order both live here, replacing what used to be a
    /// plain `Set<UUID>` with no ordering concept at all.
    @State private var selectedOrder: [UUID] = []
    @State private var level: ProfileLevel?
    @State private var isLoading = true
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var lastGeneratedAt: Date? = PortfolioPDFGenerator.lastGeneratedAt
    @State private var isPresentingPreview = false
    @State private var generatedFileURL: URL?

    private var unselectedProjects: [ScoredProject] {
        scoredProjects.filter { scored in !selectedOrder.contains(scored.id) }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if scoredProjects.isEmpty {
                ContentUnavailableView(
                    "No projects yet", systemImage: "doc.richtext",
                    description: Text("Create a project first — your portfolio is built from real ones."))
            } else {
                List {
                    if let lastGeneratedAt {
                        Section {
                            Text("Last generated \(lastGeneratedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        ForEach(selectedOrder, id: \.self) { id in
                            if let scored = scoredProjects.first(where: { $0.id == id }) {
                                projectRow(scored, isSelected: true)
                            }
                        }
                        .onMove { indices, newOffset in
                            selectedOrder.move(fromOffsets: indices, toOffset: newOffset)
                        }
                        .onDelete { indices in
                            selectedOrder.remove(atOffsets: indices)
                        }
                    } header: {
                        Text("In your portfolio")
                    } footer: {
                        Text("This is the order they'll appear in the PDF — tap Edit to drag them into place, or swipe to remove one.")
                    }
                    if !unselectedProjects.isEmpty {
                        Section {
                            ForEach(unselectedProjects) { scored in
                                projectRow(scored, isSelected: false)
                            }
                        } header: {
                            Text("Not included")
                        } footer: {
                            Text("The top projects by real activity (stars, views, real content) were pre-selected — tap any project to add it.")
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }
                .refreshable { await refresh() }
            }
        }
        .navigationTitle("Portfolio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !scoredProjects.isEmpty { EditButton() }
            }
            ToolbarItem(placement: .primaryAction) {
                if isGenerating {
                    ProgressView()
                } else {
                    Button("Generate PDF") { Task { await generate() } }
                        .disabled(selectedOrder.isEmpty)
                }
            }
        }
        .sheet(isPresented: $isPresentingPreview) {
            if let generatedFileURL {
                NavigationStack {
                    PDFPreviewView(url: generatedFileURL)
                }
            }
        }
        .sensoryFeedback(.success, trigger: isPresentingPreview) { _, newValue in newValue }
        .task { await load() }
    }

    private func projectRow(_ scored: ScoredProject, isSelected: Bool) -> some View {
        Button {
            if isSelected {
                selectedOrder.removeAll { $0 == scored.project.id }
            } else {
                selectedOrder.append(scored.project.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(scored.project.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    if let stars = scored.metrics.stars, stars > 0 {
                        Text("★ \(stars)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(scored.project.name)"
                + (scored.metrics.stars.map { $0 > 0 ? ", \($0) stars" : "" } ?? ""))
        .accessibilityValue(isSelected ? "Included" : "Not included")
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let scored = await fetchScoredProjects()
        scoredProjects = scored
        selectedOrder = scored.prefix(6).map(\.id)
    }

    /// Separate from `load()` deliberately — pull-to-refresh re-scores
    /// everything (fresh view counts, fresh GitHub stars) without
    /// discarding a selection/order the user already spent time on, the
    /// way blindly reusing `load()` here would have (it always resets to
    /// the top-6 default). Only drops ids for projects that genuinely no
    /// longer exist.
    private func refresh() async {
        let scored = await fetchScoredProjects()
        scoredProjects = scored
        let stillValidIDs = Set(scored.map(\.id))
        selectedOrder = selectedOrder.filter { stillValidIDs.contains($0) }
    }

    private func fetchScoredProjects() async -> [ScoredProject] {
        async let projectsTask: [Project] =
            SupabaseManager.shared.client
            .from("projects")
            .select()
            .eq("owner_id", value: profile.id)
            .order("created_at", ascending: false)
            .execute()
            .value
        async let levelTask = ProfileLevelService.fetch(profileID: profile.id)

        let projects = (try? await projectsTask) ?? []
        level = await levelTask

        // Fetches every project's GitHub metrics concurrently rather than
        // one project at a time — with N projects that's N round trips
        // running in parallel instead of N run back-to-back.
        var scored = await withTaskGroup(of: ScoredProject.self) { group in
            for project in projects {
                group.addTask {
                    let metrics = await fetchMetrics(for: project)
                    return ScoredProject(
                        project: project, metrics: metrics,
                        score: PortfolioProjectScorer.score(project: project, metrics: metrics))
                }
            }
            var results: [ScoredProject] = []
            for await scored in group { results.append(scored) }
            return results
        }
        scored.sort { $0.score > $1.score }
        return scored
    }

    // `nonisolated` — neither of these touches `@State`, only `provider`
    // (a plain `let`, `Sendable` via `GitProvider`'s own protocol
    // requirement) and their own parameters. Needed so the `withTaskGroup`
    // child tasks above (which don't run on the main actor) can call them
    // without hopping back to it for every single project.
    private nonisolated func fetchMetrics(for project: Project) async -> PortfolioPDFGenerator.ProjectMetrics {
        guard let githubURL = project.githubURL, !githubURL.isEmpty else {
            return PortfolioPDFGenerator.ProjectMetrics()
        }
        async let repoTask = try? await provider.repoMetadata(githubURL: githubURL)
        async let contributorsTask = try? await provider.contributorStats(githubURL: githubURL)
        return PortfolioPDFGenerator.ProjectMetrics(
            stars: await repoTask?.starCount, contributors: await contributorsTask?.count)
    }

    private func generate() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            let selectedProjects = selectedOrder.compactMap { id in
                scoredProjects.first { $0.id == id }?.project
            }
            let metricsByID = Dictionary(
                uniqueKeysWithValues: scoredProjects.map { ($0.project.id, $0.metrics) })
            let achievement = Achievement.latestUnlocked(at: level?.level ?? 0)
            let url = try await PortfolioPDFGenerator.generate(
                profile: profile, level: level, achievement: achievement, projects: selectedProjects,
                metrics: metricsByID)
            lastGeneratedAt = Date()
            generatedFileURL = url
            isPresentingPreview = true
            AnalyticsService.track("portfolio_generated", properties: ["project_count": .integer(selectedProjects.count)])
        } catch {
            CrashReporter.capture(error, context: "portfolio_generate")
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}

private struct ScoredProject: Identifiable {
    let project: Project
    let metrics: PortfolioPDFGenerator.ProjectMetrics
    let score: Int
    var id: UUID { project.id }
}
