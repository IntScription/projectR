import XCTest

@testable import ProjectR

final class PortfolioProjectScorerTests: XCTestCase {
    func testStarsWeighMoreThanViewsOrTechStackSize() {
        let barelyViewedButStarred = makeProject(viewCount: 5, techStack: [], hasDescription: false, hasCover: false)
        let heavilyViewedNoStars = makeProject(viewCount: 100, techStack: [], hasDescription: false, hasCover: false)

        let starredScore = PortfolioProjectScorer.score(
            project: barelyViewedButStarred, metrics: .init(stars: 30, contributors: nil))
        let viewedScore = PortfolioProjectScorer.score(
            project: heavilyViewedNoStars, metrics: .init(stars: nil, contributors: nil))

        // 5 + 30*5 = 155 vs. 100 + 0 = 100 — real external validation
        // (stars) should be able to outrank raw view count.
        XCTAssertGreaterThan(starredScore, viewedScore)
    }

    func testRealContentAddsToTheScore() {
        let bare = makeProject(viewCount: 0, techStack: [], hasDescription: false, hasCover: false)
        let fleshedOut = makeProject(
            viewCount: 0, techStack: ["Swift", "SwiftUI"], hasDescription: true, hasCover: true)

        let bareScore = PortfolioProjectScorer.score(project: bare, metrics: .init(stars: nil, contributors: nil))
        let fleshedOutScore = PortfolioProjectScorer.score(
            project: fleshedOut, metrics: .init(stars: nil, contributors: nil))

        XCTAssertEqual(bareScore, 0)
        // 2 tech chips * 2 = 4, + description 10, + cover 5 = 19.
        XCTAssertEqual(fleshedOutScore, 19)
    }

    private func makeProject(
        viewCount: Int, techStack: [String], hasDescription: Bool, hasCover: Bool
    ) -> Project {
        Project(
            id: UUID(), ownerID: UUID(), slug: "test", name: "Test Project",
            description: hasDescription ? "A real description." : nil, aiSummary: nil,
            coverImageURL: hasCover ? "https://example.com/cover.jpg" : nil, coverVideoURL: nil,
            category: .software, tags: [], status: .building, techStack: techStack, githubURL: nil, links: [],
            isOpenSource: false, viewCount: viewCount, createdAt: Date())
    }
}
