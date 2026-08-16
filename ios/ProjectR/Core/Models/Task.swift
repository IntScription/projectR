import Foundation

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo, inProgress = "in_progress", done
    var id: String { rawValue }

    var label: String {
        switch self {
        case .todo: "To Do"
        case .inProgress: "In Progress"
        case .done: "Done"
        }
    }
}

/// The minimum task model Forge linking needs — title, status, an owning
/// project, an optional linked branch. Not a full project-management
/// suite (no due dates, priorities, subtasks).
struct ProjectTask: Codable, Identifiable, Hashable {
    let id: UUID
    var projectID: UUID
    var number: Int
    var title: String
    var status: TaskStatus
    var branchName: String?
    var createdBy: UUID
    var assigneeID: UUID?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case projectID = "project_id"
        case number, title, status
        case branchName = "branch_name"
        case createdBy = "created_by"
        case assigneeID = "assignee_id"
        case createdAt = "created_at"
    }
}
