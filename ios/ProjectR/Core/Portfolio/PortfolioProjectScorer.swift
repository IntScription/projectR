import Foundation

/// The "which projects go in the portfolio by default" formula, pulled
/// out of `PortfolioBuilderView` into its own type for one concrete
/// reason: a `nonisolated` method on a SwiftUI View struct can't be
/// exercised from a test target the way a plain type can. Real,
/// defensible signals only — real GitHub stars weighted highest (external
/// validation), then view count, then how much real content the project
/// actually has. No fabricated "quality" score.
enum PortfolioProjectScorer {
    static func score(project: Project, metrics: PortfolioPDFGenerator.ProjectMetrics) -> Int {
        var value = project.viewCount + (metrics.stars ?? 0) * 5 + project.techStack.count * 2
        if let description = project.description, !description.isEmpty { value += 10 }
        if project.coverImageURL != nil { value += 5 }
        return value
    }
}
