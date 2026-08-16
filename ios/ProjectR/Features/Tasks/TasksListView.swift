import SwiftUI

/// Navigation value for pushing a task's detail — carries the parent
/// `Project` alongside the task the same way `ForgeRoute` carries it for
/// Forge, since `TaskDetailView` needs the project's `githubURL` to talk
/// to `GitProvider`.
struct TaskRoute: Hashable {
    let task: ProjectTask
    let project: Project
}

/// Reached via the checklist toolbar button on `ProjectDetailView`,
/// alongside the Forge hammer button. Grouped by status rather than a
/// flat list — "what's left to do" is the question this screen answers.
struct TasksListView: View {
    let project: Project

    @State private var tasks: [ProjectTask] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isPresentingCreate = false

    var body: some View {
        Group {
            if isLoading && tasks.isEmpty {
                ProgressView()
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn't load tasks", systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage))
            } else if tasks.isEmpty {
                ContentUnavailableView(
                    "No tasks yet", systemImage: "checklist",
                    description: Text("Tap + to add the first one."))
            } else {
                List {
                    ForEach(TaskStatus.allCases) { status in
                        let group = tasks.filter { $0.status == status }
                        if !group.isEmpty {
                            Section(status.label) {
                                ForEach(group) { task in
                                    NavigationLink(value: TaskRoute(task: task, project: project)) {
                                        taskRow(task)
                                    }
                                }
                            }
                        }
                    }
                }
                // TaskDetailView (pushed elsewhere in the stack) can change
                // a task's branch/PR status; this view instance isn't
                // recreated on pop-back, so pull-to-refresh is how its list
                // picks that up rather than a callback threaded through a
                // navigationDestination registered up at ProjectDetailView.
                .refreshable { await load() }
                .floatingTabBarClearance()
            }
        }
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New task")
            }
        }
        .sheet(isPresented: $isPresentingCreate) {
            NewTaskSheet(projectID: project.id) { created in
                tasks.insert(created, at: 0)
            }
        }
        .task { await load() }
    }

    private func taskRow(_ task: ProjectTask) -> some View {
        HStack(spacing: 8) {
            Text("#\(task.number)")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(task.title)
            Spacer()
            if task.branchName != nil {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            tasks =
                try await SupabaseManager.shared.client
                .from("tasks")
                .select()
                .eq("project_id", value: project.id)
                .order("number", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}

/// Title-only creation — matches the scope call against a full
/// project-management suite (no due dates, priorities, assignee picker
/// at creation time).
private struct NewTaskSheet: View {
    let projectID: UUID
    var onCreated: (ProjectTask) -> Void

    @State private var title = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Task title", text: $title)
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isCreating {
                        ProgressView()
                    } else {
                        Button("Create") { Task { await create() } }
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.height(180)])
    }

    private func create() async {
        guard let userID = SupabaseManager.shared.client.auth.currentSession?.user.id else { return }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            let created: ProjectTask =
                try await SupabaseManager.shared.client
                .from("tasks")
                .insert(
                    NewTask(
                        projectID: projectID,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        createdBy: userID)
                )
                .select()
                .single()
                .execute()
                .value
            onCreated(created)
            dismiss()
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}

private struct NewTask: Encodable {
    let projectID: UUID
    let title: String
    let createdBy: UUID

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case title
        case createdBy = "created_by"
    }
}
