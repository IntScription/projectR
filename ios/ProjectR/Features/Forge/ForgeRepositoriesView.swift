import SwiftUI

/// Every repo on the connected GitHub account — not just the ones
/// already attached to a ProjectR project. Tapping a repo browses its
/// files (default branch, read-only — same as the Forge dashboard's own
/// "Files" link, just without a ProjectR project behind it); the copy
/// icon is its own separate tap target for grabbing the repo's URL to
/// paste into `CreateProjectView`'s GitHub URL field, which already
/// auto-fills description/tags/tech-stack from whatever real repo you
/// paste.
struct ForgeRepositoriesView: View {
    @State private var repos: [GitHubRepo] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var copiedRepoID: Int?
    @State private var isPresentingCopyToast = false
    @State private var selectedInsightsRepo: GitHubRepo?

    var body: some View {
        Group {
            if isLoading && repos.isEmpty {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn't load repositories", systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage))
            } else if repos.isEmpty {
                ContentUnavailableView("No repositories found", systemImage: "shippingbox")
            } else {
                // A genuinely fixed header (not a `List` section header,
                // which scrolls away with its section) — same "identity
                // stays put, only content scrolls" structure ProfileView
                // already uses, so the tech-stack chips never move while
                // browsing the repo list beneath them.
                VStack(spacing: 0) {
                    if !techStack.isEmpty {
                        techStackHeader
                    }
                    List(repos) { repo in
                        row(for: repo)
                    }
                    .listStyle(.plain)
                    .floatingTabBarClearance()
                }
            }
        }
        .navigationTitle("Your Repositories")
        .navigationBarTitleDisplayMode(.inline)
        .copyToast("Link copied to clipboard", isPresented: $isPresentingCopyToast)
        // `item:`-driven rather than `ForgeDestination`'s usual
        // `value:`-based `NavigationLink` — the insights button already
        // sits inside this row's own `NavigationLink` (files browsing),
        // and nesting a second `NavigationLink` inside the first doesn't
        // reliably get its own independent tap target the way a plain
        // `Button` does, so this one drives navigation from a local
        // optional instead.
        .navigationDestination(item: $selectedInsightsRepo) { repo in
            ForgeRepoInsightsView(githubURL: repo.htmlURL, projectID: nil)
        }
        .task { await load() }
    }

    /// Every repo already carries its own primary language for free (no
    /// extra API calls beyond the one `myRepositories()` fetch already
    /// does) — counting how many repos share each one is the cheapest
    /// real signal for "what do you actually work in," learned from the
    /// whole account rather than just whatever's been turned into a
    /// ProjectR project so far.
    private var techStack: [(language: String, count: Int)] {
        Dictionary(grouping: repos.compactMap(\.language), by: { $0 })
            .mapValues(\.count)
            .sorted { $0.value > $1.value }
            .map { (language: $0.key, count: $0.value) }
    }

    private var techStackHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your tech stack")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(techStack, id: \.language) { entry in
                        HStack(spacing: 4) {
                            Text(entry.language).font(.caption.weight(.semibold))
                            Text("\(entry.count)").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
        .textCase(nil)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    /// Whole row = browse files (the primary, expected action for a repo
    /// row); the copy icon is its own independent tap target, same
    /// "avatar vs. rest of card" split used elsewhere in this app so the
    /// two actions never fight over one hit area.
    private func row(for repo: GitHubRepo) -> some View {
        NavigationLink(
            value: ForgeDestination.files(githubURL: repo.htmlURL, path: "", projectID: nil, branch: nil)
        ) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(repo.name).font(.subheadline.weight(.semibold))
                        if repo.isPrivate {
                            Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if let description = repo.description, !description.isEmpty {
                        Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if let language = repo.language {
                        Text(language).font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor)
                    }
                }
                .foregroundStyle(.primary)
                Spacer()
                insightsButton(for: repo)
                copyButton(for: repo)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .contextMenu {
            Button {
                copy(repo)
            } label: {
                Label("Copy Link", systemImage: "doc.on.doc")
            }
            if let url = URL(string: repo.htmlURL) {
                Link(destination: url) {
                    Label("Open in GitHub", systemImage: "safari")
                }
            }
        }
    }

    /// A third, independent tap target alongside the copy button — a repo
    /// row's primary tap stays "browse files" (kept intentionally direct
    /// per earlier feedback), so strengths/weaknesses + graphs get their
    /// own explicit entry point rather than replacing that.
    private func insightsButton(for repo: GitHubRepo) -> some View {
        Button {
            selectedInsightsRepo = repo
        } label: {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View insights")
    }

    private func copyButton(for repo: GitHubRepo) -> some View {
        Button {
            copy(repo)
        } label: {
            Image(systemName: copiedRepoID == repo.id ? "checkmark" : "doc.on.doc")
                .foregroundStyle(copiedRepoID == repo.id ? .green : .secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy repository link")
    }

    private func copy(_ repo: GitHubRepo) {
        UIPasteboard.general.string = repo.htmlURL
        withAnimation(.spring(duration: 0.25)) { copiedRepoID = repo.id }
        isPresentingCopyToast = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.spring(duration: 0.25)) {
                if copiedRepoID == repo.id { copiedRepoID = nil }
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            repos = try await GitHubService.myRepositories()
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}
