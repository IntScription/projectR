import XCTest

@testable import ProjectR

final class PortfolioHTMLTemplateTests: XCTestCase {
    /// The real correctness risk this template has: a project name or bio
    /// containing HTML-significant characters must never reach the output
    /// unescaped — that's not just a rendering glitch, it can break the
    /// document's structure (e.g. a stray `"` inside an `href` attribute).
    func testUserSuppliedTextIsHTMLEscaped() {
        let profile = makeProfile(displayName: "Al Ex", bio: "Loves <scripting> & \"quotes\"")
        let project = makeProject(
            name: "<script>alert(1)</script>", description: "Tags & <b>bold</b> stuff")

        let html = PortfolioHTMLTemplate.build(
            profile: profile, level: nil, achievement: nil, projects: [project], metrics: [:])

        XCTAssertFalse(html.contains("<script>alert(1)</script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertTrue(html.contains("Tags &amp; &lt;b&gt;bold&lt;/b&gt; stuff"))
        XCTAssertTrue(html.contains("&quot;quotes&quot;"))
    }

    func testMissingOptionalDataDoesNotCrashOrLeaveHoles() {
        let profile = makeProfile(displayName: "No Extras", bio: nil)
        let html = PortfolioHTMLTemplate.build(
            profile: profile, level: nil, achievement: nil, projects: [], metrics: [:])

        XCTAssertTrue(html.contains("No Extras"))
        XCTAssertTrue(html.contains("<!doctype html>"))
    }

    func testRealMetricsAppearInTheProjectCard() {
        let profile = makeProfile(displayName: "Star Haver", bio: nil)
        let project = makeProject(name: "Popular Repo", description: "A well-starred project.")
        let html = PortfolioHTMLTemplate.build(
            profile: profile, level: nil, achievement: nil, projects: [project],
            metrics: [project.id: .init(stars: 42, contributors: 3)])

        XCTAssertTrue(html.contains("★ 42"))
        XCTAssertTrue(html.contains("3 contributors"))
    }

    private func makeProfile(displayName: String, bio: String?) -> Profile {
        Profile(
            id: UUID(), username: "testuser", displayName: displayName, avatarURL: nil, bannerURL: nil, bio: bio,
            skills: [], links: [], role: nil)
    }

    private func makeProject(name: String, description: String) -> Project {
        Project(
            id: UUID(), ownerID: UUID(), slug: "test", name: name, description: description, aiSummary: nil,
            coverImageURL: nil, coverVideoURL: nil, category: .software, tags: [], status: .building,
            techStack: ["Swift"], githubURL: nil, links: [], isOpenSource: false, viewCount: 0, createdAt: Date())
    }
}
