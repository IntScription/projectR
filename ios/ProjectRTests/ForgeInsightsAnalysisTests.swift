import XCTest

@testable import ProjectR

final class ForgeInsightsAnalysisTests: XCTestCase {
    func testActiveRepoWithHealthySignalsProducesOnlyStrengths() throws {
        let commitActivity = try decodeCommitActivity(recentTotals: [5, 3, 4, 6])
        let contributors = try decodeContributors(totals: [40, 12, 3])
        let issues = ForgeIssueVelocity(openCount: 0, closedCount: 20, averageDaysToClose: 2)
        let pulls = ForgePullRequestVelocity(
            openCount: 1, mergedCount: 18, closedWithoutMergeCount: 2, averageDaysToMerge: 1, mergeRate: 0.9)

        let result = ForgeInsightsAnalysis.analyze(
            commitActivity: commitActivity, contributors: contributors, issues: issues, pulls: pulls)

        XCTAssertTrue(result.strengths.contains { $0.contains("Actively maintained") })
        XCTAssertTrue(result.strengths.contains { $0.contains("3 contributors") })
        XCTAssertTrue(result.strengths.contains { $0.contains("No open issues") })
        XCTAssertTrue(result.strengths.contains { $0.contains("90% of pull requests") })
        XCTAssertTrue(result.weaknesses.isEmpty, "Expected no weaknesses, got \(result.weaknesses)")
    }

    func testStaleSingleContributorRepoProducesWeaknesses() throws {
        // Eight weeks of real history, all zero — genuinely stale, not
        // just "no data yet."
        let commitActivity = try decodeCommitActivity(recentTotals: Array(repeating: 0, count: 8))
        let contributors = try decodeContributors(totals: [7])
        let issues = ForgeIssueVelocity(openCount: 45, closedCount: 2, averageDaysToClose: 90)
        let pulls = ForgePullRequestVelocity(
            openCount: 20, mergedCount: 1, closedWithoutMergeCount: 9, averageDaysToMerge: nil, mergeRate: 0.1)

        let result = ForgeInsightsAnalysis.analyze(
            commitActivity: commitActivity, contributors: contributors, issues: issues, pulls: pulls)

        XCTAssertTrue(result.weaknesses.contains { $0.contains("No commits in the last 8 weeks") })
        XCTAssertTrue(result.weaknesses.contains { $0.contains("Single contributor") })
        XCTAssertTrue(result.weaknesses.contains { $0.contains("Large open-issue backlog (45)") })
        XCTAssertTrue(result.weaknesses.contains { $0.contains("90 days on average") })
        XCTAssertTrue(result.weaknesses.contains { $0.contains("10% of pull requests") })
        XCTAssertTrue(result.weaknesses.contains { $0.contains("20 open pull requests") })
    }

    func testEmptyRepoProducesNeitherStrengthsNorWeaknesses() throws {
        let commitActivity = try decodeCommitActivity(recentTotals: [])
        let result = ForgeInsightsAnalysis.analyze(
            commitActivity: commitActivity, contributors: [],
            issues: ForgeIssueVelocity(openCount: 0, closedCount: 0, averageDaysToClose: nil),
            pulls: ForgePullRequestVelocity(
                openCount: 0, mergedCount: 0, closedWithoutMergeCount: 0, averageDaysToMerge: nil, mergeRate: nil))

        XCTAssertTrue(result.strengths.isEmpty)
        XCTAssertTrue(result.weaknesses.isEmpty)
    }

    private func decodeCommitActivity(recentTotals: [Int]) throws -> [ForgeCommitActivityWeek] {
        let entries = recentTotals.enumerated().map { index, total in
            #"{"week": \#(1_700_000_000 + index * 604_800), "total": \#(total), "days": [0,0,0,0,0,0,0]}"#
        }
        let json = "[\(entries.joined(separator: ","))]"
        return try JSONDecoder().decode([ForgeCommitActivityWeek].self, from: Data(json.utf8))
    }

    private func decodeContributors(totals: [Int]) throws -> [ForgeContributorStat] {
        let entries = totals.enumerated().map { index, total in
            #"{"author": {"login": "user\#(index)", "avatar_url": null}, "total": \#(total)}"#
        }
        let json = "[\(entries.joined(separator: ","))]"
        return try JSONDecoder().decode([ForgeContributorStat].self, from: Data(json.utf8))
    }
}
