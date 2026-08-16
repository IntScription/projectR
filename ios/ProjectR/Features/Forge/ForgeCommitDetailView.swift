import SwiftUI

struct ForgeCommitDetailView: View {
    let githubURL: String
    let sha: String
    let projectID: UUID
    private let provider: GitProvider = GitHubProvider()

    @State private var detail: ForgeCommitDetail?
    @State private var tasks: [ProjectTask] = []
    @State private var project: Project?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isPresentingSharePicker = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn't load this commit", systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage))
            } else if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(for: detail)
                        ForEach(detail.files) { file in
                            FileDiffView(file: file)
                        }
                    }
                    .padding(16)
                }
                .floatingTabBarClearance()
            }
        }
        .navigationTitle(String(sha.prefix(7)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if detail != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingSharePicker = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                }
            }
        }
        .sheet(isPresented: $isPresentingSharePicker) {
            if let detail {
                SendToFollowerSheet(
                    messageBody: "Commit \(String(sha.prefix(7))) on ProjectR: \(detail.message)",
                    metadata: ForgeShareMetadata(
                        kind: "forge_commit", githubURL: githubURL, projectID: projectID, sha: sha,
                        title: detail.message.components(separatedBy: "\n").first ?? detail.message,
                        subtitle: "Commit \(String(sha.prefix(7))) · \(detail.authorName)")
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .task { await load() }
    }

    private func header(for detail: ForgeCommitDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(detail.message).font(.headline)
            HStack(spacing: 6) {
                Text(detail.authorName)
                Text("·")
                Text(detail.authorDate, format: .dateTime.month(.abbreviated).day().hour().minute())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("\(detail.files.count) file\(detail.files.count == 1 ? "" : "s") changed")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            if let project, let task = TaskLinking.referencedTask(in: detail.message, tasks: tasks) {
                TaskChip(task: task, project: project)
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let detailTask = provider.commitDetail(githubURL: githubURL, sha: sha)
            async let tasksTask: [ProjectTask] =
                SupabaseManager.shared.client
                .from("tasks").select().eq("project_id", value: projectID).execute().value
            async let projectTask: Project =
                SupabaseManager.shared.client
                .from("projects").select().eq("id", value: projectID).single().execute().value
            detail = try await detailTask
            tasks = (try? await tasksTask) ?? []
            project = try? await projectTask
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}

/// Renders one file's unified-diff `patch` text with +/- line coloring —
/// plain text diff, deliberately no syntax highlighting inside it either
/// (matches the code viewer's own Phase 1 scope cut).
private struct FileDiffView: View {
    let file: ForgeFileDiff

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(file.filename).font(.subheadline.weight(.semibold))
                Spacer()
                Text("+\(file.additions)").foregroundStyle(.green)
                Text("-\(file.deletions)").foregroundStyle(.red)
            }
            .font(.caption)
            .padding(10)
            .background(Color(.secondarySystemGroupedBackground))

            if let patch = file.patch {
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(patch.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                            diffLine(line)
                        }
                    }
                }
            } else {
                Text("No preview available for this change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
        }
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func diffLine(_ line: String) -> some View {
        let (background, textColor): (Color, Color) =
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                (.green.opacity(0.15), .primary)
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                (.red.opacity(0.15), .primary)
            } else if line.hasPrefix("@@") {
                (Color.secondary.opacity(0.12), .secondary)
            } else {
                (.clear, .primary)
            }

        Text(line.isEmpty ? " " : line)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 1)
            .background(background)
    }
}
