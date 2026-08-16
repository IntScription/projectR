import Charts
import SwiftUI

/// Real GitHub-derived analytics for a repo — a health summary plus every
/// graph a dev would actually want to see. Everything except "Star
/// Growth" is fetched live from GitHub's own Stats API each time this
/// screen opens: GitHub already buckets that data by week and keeps it
/// refreshed server-side, so there's nothing for this app to cache or
/// recompute to satisfy "the graphs keep updating" — they already do,
/// for free. "Star Growth" is the one exception: GitHub's REST API has no
/// historical star/issue-count endpoint, so that one chart reads from
/// `repo_analytics_snapshots`, a table this app fills in weekly via a
/// scheduled Edge Function (`capture-repo-snapshots`) — only for repos
/// attached to a ProjectR project, since that's the point at which a repo
/// is worth tracking long-term.
struct ForgeRepoInsightsView: View {
    let githubURL: String
    let projectID: UUID?
    private let provider: GitProvider = GitHubProvider()

    @State private var repo: Loadable<ForgeRepo> = .loading
    @State private var commitActivity: Loadable<[ForgeCommitActivityWeek]> = .loading
    @State private var codeFrequency: Loadable<[ForgeCodeFrequencyWeek]> = .loading
    @State private var contributors: Loadable<[ForgeContributorStat]> = .loading
    @State private var punchCard: Loadable<[ForgePunchCardEntry]> = .loading
    @State private var languages: Loadable<[ForgeLanguageBytes]> = .loading
    @State private var issueVelocity: Loadable<ForgeIssueVelocity> = .loading
    @State private var pullVelocity: Loadable<ForgePullRequestVelocity> = .loading
    @State private var snapshots: Loadable<[ForgeRepoAnalyticsSnapshot]> = .loading

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                healthSection
                commitActivitySection
                codeFrequencySection
                punchCardSection
                contributorsSection
                languageMixSection
                velocitySection
                starGrowthSection
            }
            .padding(20)
        }
        .refreshable { await load() }
        .navigationTitle(repo.value?.name ?? "Insights")
        .navigationBarTitleDisplayMode(.inline)
        .floatingTabBarClearance()
        .task { await load() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var healthSection: some View {
        card("Health") {
            if let activity = commitActivity.value, let contribs = contributors.value,
                let issues = issueVelocity.value, let pulls = pullVelocity.value
            {
                let analysis = ForgeInsightsAnalysis.analyze(
                    commitActivity: activity, contributors: contribs, issues: issues, pulls: pulls)
                if analysis.strengths.isEmpty && analysis.weaknesses.isEmpty {
                    Text("Not enough activity yet to analyze.").font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(analysis.strengths, id: \.self) { line in
                            Label(line, systemImage: "checkmark.circle.fill")
                                .font(.subheadline).foregroundStyle(.green)
                        }
                        ForEach(analysis.weaknesses, id: \.self) { line in
                            Label(line, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline).foregroundStyle(.orange)
                        }
                    }
                }
            } else if commitActivity.isFailed || contributors.isFailed || issueVelocity.isFailed
                || pullVelocity.isFailed
            {
                Text("Couldn't compute a health summary for this repo.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 40)
            }
        }
    }

    private var commitActivitySection: some View {
        card("Commit Activity") {
            loadableContent(commitActivity) { weeks in
                if weeks.allSatisfy({ $0.total == 0 }) {
                    Text("No commits in the last year.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Chart(weeks) { week in
                        BarMark(
                            x: .value("Week", week.weekStart, unit: .weekOfYear),
                            y: .value("Commits", week.total)
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .month, count: 3)) { AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                    .frame(height: 140)
                }
            }
        }
    }

    private var codeFrequencySection: some View {
        card("Code Frequency") {
            loadableContent(codeFrequency) { weeks in
                if weeks.allSatisfy({ $0.additions == 0 && $0.deletions == 0 }) {
                    Text("No code changes in the last year.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Chart(weeks) { week in
                        BarMark(
                            x: .value("Week", week.weekStart, unit: .weekOfYear),
                            y: .value("Additions", week.additions)
                        )
                        .foregroundStyle(.green)
                        // `deletions` is already a negative delta straight
                        // from GitHub's response, so plotting it as-is on
                        // the same axis is what produces the diverging
                        // above/below-zero look.
                        BarMark(
                            x: .value("Week", week.weekStart, unit: .weekOfYear),
                            y: .value("Deletions", week.deletions)
                        )
                        .foregroundStyle(.red)
                    }
                    .frame(height: 140)
                }
            }
        }
    }

    private var punchCardSection: some View {
        card("Commit Punch Card") {
            loadableContent(punchCard) { entries in
                if entries.allSatisfy({ $0.commits == 0 }) {
                    Text("Not enough commit history yet.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Chart(entries, id: \.self) { entry in
                        RectangleMark(
                            x: .value("Hour", entry.hour), y: .value("Day", Self.dayName(entry.day))
                        )
                        .foregroundStyle(by: .value("Commits", entry.commits))
                    }
                    .chartForegroundStyleScale(range: Gradient(colors: [Color.accentColor.opacity(0.08), Color.accentColor]))
                    .frame(height: 180)
                }
            }
        }
    }

    private var contributorsSection: some View {
        card("Contributors") {
            loadableContent(contributors) { list in
                if list.isEmpty {
                    Text("No contributor data yet.").font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(list.prefix(8)) { contributor in
                            HStack {
                                Text(contributor.login).font(.subheadline)
                                Spacer()
                                Text("\(contributor.total) commit\(contributor.total == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var languageMixSection: some View {
        card("Language Mix") {
            loadableContent(languages) { list in
                if list.isEmpty {
                    Text("No language data.").font(.caption).foregroundStyle(.secondary)
                } else {
                    let total = list.reduce(0) { $0 + $1.bytes }
                    Chart(list) { entry in
                        SectorMark(angle: .value("Bytes", entry.bytes), innerRadius: .ratio(0.6))
                            .foregroundStyle(by: .value("Language", entry.language))
                    }
                    .frame(height: 180)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(list.prefix(6)) { entry in
                            HStack {
                                Text(entry.language).font(.caption)
                                Spacer()
                                Text(total > 0 ? "\(Int((Double(entry.bytes) / Double(total) * 100).rounded()))%" : "—")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var velocitySection: some View {
        card("Issue & PR Velocity") {
            VStack(alignment: .leading, spacing: 10) {
                loadableContent(issueVelocity) { issues in
                    statRow("Open Issues", "\(issues.openCount)")
                    statRow("Closed Issues", "\(issues.closedCount)")
                    if let avg = issues.averageDaysToClose {
                        statRow("Avg. Time to Close", "\(Int(avg.rounded())) day\(Int(avg.rounded()) == 1 ? "" : "s")")
                    }
                }
                Divider()
                loadableContent(pullVelocity) { pulls in
                    statRow("Open PRs", "\(pulls.openCount)")
                    statRow("Merged PRs", "\(pulls.mergedCount)")
                    if let rate = pulls.mergeRate {
                        statRow("Merge Rate", "\(Int((rate * 100).rounded()))%")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var starGrowthSection: some View {
        card("Star Growth") {
            if projectID == nil {
                Text("Attach this repo to a ProjectR project to start tracking its growth over time.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                loadableContent(snapshots) { rows in
                    let plotted = rows.compactMap { row -> (Date, Int)? in
                        guard let date = row.capturedAt else { return nil }
                        return (date, row.stars)
                    }
                    if plotted.count < 2 {
                        Text("History starts building this week — check back after a few weekly snapshots.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Chart(plotted, id: \.0) { date, stars in
                            LineMark(x: .value("Date", date), y: .value("Stars", stars))
                                .foregroundStyle(Color.accentColor)
                            PointMark(x: .value("Date", date), y: .value("Stars", stars))
                                .foregroundStyle(Color.accentColor)
                        }
                        .frame(height: 140)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func loadableContent<T, Content: View>(
        _ loadable: Loadable<T>, @ViewBuilder content: (T) -> Content
    ) -> some View {
        switch loadable {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 60)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.secondary)
        case .loaded(let value):
            content(value)
        }
    }

    /// GitHub's punch card day index is documented as 0 = Sunday — hard
    /// enough that using `Calendar.shortWeekdaySymbols` (locale-dependent
    /// first-weekday) could silently mislabel every bar, so this is fixed
    /// regardless of the device's locale/calendar settings.
    private static func dayName(_ day: Int) -> String {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return names.indices.contains(day) ? names[day] : "?"
    }

    private func load() async {
        async let repoTask = provider.repoMetadata(githubURL: githubURL)
        async let commitActivityTask = provider.commitActivity(githubURL: githubURL)
        async let codeFrequencyTask = provider.codeFrequency(githubURL: githubURL)
        async let contributorsTask = provider.contributorStats(githubURL: githubURL)
        async let punchCardTask = provider.punchCard(githubURL: githubURL)
        async let languagesTask = provider.languageBreakdown(githubURL: githubURL)
        async let issuesTask = provider.issueVelocity(githubURL: githubURL)
        async let pullsTask = provider.pullRequestVelocity(githubURL: githubURL)

        // `async let` bindings can't be captured inside another closure
        // (a hard Swift restriction, not just an escaping-closure
        // concern) — each has to be awaited directly here rather than
        // routed through a shared closure-taking helper.
        do { repo = .loaded(try await repoTask) } catch { repo = .failed(error.localizedDescription) }
        do {
            commitActivity = .loaded(try await commitActivityTask)
        } catch { commitActivity = .failed(error.localizedDescription) }
        do {
            codeFrequency = .loaded(try await codeFrequencyTask)
        } catch { codeFrequency = .failed(error.localizedDescription) }
        do {
            contributors = .loaded(try await contributorsTask)
        } catch { contributors = .failed(error.localizedDescription) }
        do {
            punchCard = .loaded(try await punchCardTask)
        } catch { punchCard = .failed(error.localizedDescription) }
        do {
            languages = .loaded(try await languagesTask)
        } catch { languages = .failed(error.localizedDescription) }
        do {
            issueVelocity = .loaded(try await issuesTask)
        } catch { issueVelocity = .failed(error.localizedDescription) }
        do {
            pullVelocity = .loaded(try await pullsTask)
        } catch { pullVelocity = .failed(error.localizedDescription) }

        if projectID != nil {
            do {
                snapshots = .loaded(try await loadSnapshots())
            } catch { snapshots = .failed(error.localizedDescription) }
        }
    }

    private func loadSnapshots() async throws -> [ForgeRepoAnalyticsSnapshot] {
        try await SupabaseManager.shared.client
            .from("repo_analytics_snapshots")
            .select()
            .eq("github_url", value: githubURL)
            .order("captured_at")
            .execute()
            .value
    }
}

private enum Loadable<T> {
    case loading
    case loaded(T)
    case failed(String)

    var value: T? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
