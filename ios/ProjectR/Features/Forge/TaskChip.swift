import SwiftUI

/// A small tappable "#N title" capsule linking a commit to the task it
/// references (via `TaskLinking.referencedTask`) — shown under a commit
/// row or a commit's detail header when a match is found.
struct TaskChip: View {
    let task: ProjectTask
    let project: Project

    var body: some View {
        NavigationLink(value: TaskRoute(task: task, project: project)) {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                Text("#\(task.number) \(task.title)")
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}
