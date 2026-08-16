import Foundation

/// Scans a commit message for `#<number>` and matches it against a
/// project's task numbers — no server-side link table needed, this is
/// cheap to compute from data already being fetched for the commit list.
enum TaskLinking {
    /// The first task (if any) referenced by `message` that also exists
    /// in `tasks` — commit messages can reference numbers that don't
    /// correspond to a real task (a PR number, an unrelated issue on
    /// GitHub itself), so this only returns a match that's actually one
    /// of *this* project's tasks.
    static func referencedTask(in message: String, tasks: [ProjectTask]) -> ProjectTask? {
        let numbers = message.matches(of: /#(\d+)/).compactMap { Int($0.1) }
        guard !numbers.isEmpty else { return nil }
        return tasks.first { numbers.contains($0.number) }
    }
}
