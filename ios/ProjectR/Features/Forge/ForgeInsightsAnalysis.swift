import Foundation

/// Rule-based strengths/weaknesses derived from real, already-fetched
/// signals — no LLM narrative, no invented opinions. Every line here
/// traces back to a number the rest of `ForgeRepoInsightsView` also shows,
/// so nothing on the "Health" card can say something the graphs disagree
/// with.
enum ForgeInsightsAnalysis {
    static func analyze(
        commitActivity: [ForgeCommitActivityWeek], contributors: [ForgeContributorStat],
        issues: ForgeIssueVelocity, pulls: ForgePullRequestVelocity
    ) -> (strengths: [String], weaknesses: [String]) {
        var strengths: [String] = []
        var weaknesses: [String] = []

        let recentWeeks = Array(commitActivity.suffix(4))
        let recentCommits = recentWeeks.reduce(0) { $0 + $1.total }
        let lastEightWeeks = Array(commitActivity.suffix(8)).reduce(0) { $0 + $1.total }
        if recentCommits > 0 {
            strengths.append("Actively maintained — \(recentCommits) commit\(recentCommits == 1 ? "" : "s") in the last 4 weeks")
        } else if lastEightWeeks == 0 && !commitActivity.isEmpty {
            weaknesses.append("No commits in the last 8 weeks")
        }

        if contributors.count >= 2 {
            strengths.append("\(contributors.count) contributors — not a single point of failure")
        } else if contributors.count == 1 {
            weaknesses.append("Single contributor — bus factor risk")
        }

        if issues.openCount == 0 && issues.closedCount > 0 {
            strengths.append("No open issues")
        } else if issues.openCount > 20 {
            weaknesses.append("Large open-issue backlog (\(issues.openCount))")
        }
        if let avgDays = issues.averageDaysToClose, avgDays <= 7 {
            strengths.append("Issues typically closed within \(Int(avgDays.rounded())) day\(Int(avgDays.rounded()) == 1 ? "" : "s")")
        } else if let avgDays = issues.averageDaysToClose, avgDays > 30 {
            weaknesses.append("Issues take \(Int(avgDays.rounded())) days on average to close")
        }

        if let mergeRate = pulls.mergeRate {
            let percent = Int((mergeRate * 100).rounded())
            if mergeRate >= 0.7 {
                strengths.append("\(percent)% of pull requests get merged")
            } else if mergeRate < 0.3 && (pulls.mergedCount + pulls.closedWithoutMergeCount) >= 5 {
                weaknesses.append("Only \(percent)% of pull requests get merged")
            }
        }
        if pulls.openCount > 15 {
            weaknesses.append("\(pulls.openCount) open pull requests awaiting review")
        }

        return (strengths, weaknesses)
    }
}
