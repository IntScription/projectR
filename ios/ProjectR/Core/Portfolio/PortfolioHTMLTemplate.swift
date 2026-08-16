import Foundation

/// Builds the HTML `PortfolioPDFGenerator` renders to PDF. Every value
/// here traces to a real field already on `Profile`/`ProfileLevel`/
/// `Achievement`/`Project`, or a metric already fetched elsewhere in the
/// app (GitHub stars/contributors, via the same `GitProvider` the Forge
/// Insights screen uses) — nothing here is invented or LLM-narrated at
/// render time; the one AI-authored piece (`Project.aiSummary`) was
/// already generated and reviewed earlier, in the project edit flow.
enum PortfolioHTMLTemplate {
    static func build(
        profile: Profile, level: ProfileLevel?, achievement: Achievement?, projects: [Project],
        metrics: [UUID: PortfolioPDFGenerator.ProjectMetrics]
    ) -> String {
        let generatedDate = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
        let profileURL = ShareLinks.profile(username: profile.username).absoluteString

        return """
            <!doctype html>
            <html>
            <head>
            <meta charset="utf-8">
            <style>\(css)</style>
            </head>
            <body>
            \(header(profile: profile, level: level))
            \(aboutSection(level: level, achievement: achievement))
            \(projectsSection(projects: projects, metrics: metrics))
            <div class="footer">Generated \(esc(generatedDate)) &middot; \(esc(profileURL))</div>
            </body>
            </html>
            """
    }

    private static func header(profile: Profile, level: ProfileLevel?) -> String {
        let avatar =
            profile.avatarURL.map { "<img class=\"avatar\" src=\"\(esc($0))\">" } ?? ""
        let tagline = level.map { esc($0.levelLabel) } ?? esc(profile.role ?? "")
        let bio = profile.bio.map { "<p class=\"bio\">\(esc($0))</p>" } ?? ""
        let links = profile.links.map { link in
            "<a class=\"link-chip\" href=\"\(esc(link.url))\">\(esc(link.label))</a>"
        }.joined()

        return """
            <div class="header">
              \(avatar)
              <div class="header-text">
                <h1>\(esc(profile.displayName))</h1>
                <div class="tagline">\(tagline)</div>
                \(bio)
                <div class="links">\(links)</div>
              </div>
            </div>
            """
    }

    private static func aboutSection(level: ProfileLevel?, achievement: Achievement?) -> String {
        guard let level else { return "" }
        let skills = level.skills.prefix(8).map { skill in
            "<span class=\"skill-chip\">\(esc(skill.name)) &middot; \(skill.level)</span>"
        }.joined()
        let badge =
            achievement.map {
                "<div class=\"achievement\">🏅 \(esc($0.title)) &mdash; \(esc($0.subtitle))</div>"
            } ?? ""

        return """
            <div class="section">
              <h2>About</h2>
              <p>\(esc(level.summary))</p>
              <div class="chips">\(skills)</div>
              \(badge)
            </div>
            """
    }

    private static func projectsSection(
        projects: [Project], metrics: [UUID: PortfolioPDFGenerator.ProjectMetrics]
    ) -> String {
        guard !projects.isEmpty else { return "" }
        let cards = projects.map { project in
            projectCard(project, metrics: metrics[project.id])
        }.joined()
        return """
            <div class="section">
              <h2>Projects</h2>
              \(cards)
            </div>
            """
    }

    private static func projectCard(_ project: Project, metrics: PortfolioPDFGenerator.ProjectMetrics?) -> String {
        let bio = project.aiSummary ?? project.description ?? ""
        let techStack = project.techStack.map { "<span class=\"tech-chip\">\(esc($0))</span>" }.joined()

        var statLines: [String] = []
        if let stars = metrics?.stars { statLines.append("★ \(stars)") }
        if let contributors = metrics?.contributors {
            statLines.append("\(contributors) contributor\(contributors == 1 ? "" : "s")")
        }
        let stats = statLines.isEmpty ? "" : "<div class=\"stats\">\(esc(statLines.joined(separator: " · ")))</div>"

        let link =
            (project.githubURL ?? project.links.first?.url).map {
                "<a class=\"project-link\" href=\"\(esc($0))\">\(esc($0))</a>"
            } ?? ""

        return """
            <div class="project-card">
              <div class="project-title-row">
                <span class="project-name">\(esc(project.name))</span>
                <span class="status-chip">\(esc(project.status.rawValue.capitalized))</span>
              </div>
              \(bio.isEmpty ? "" : "<p class=\"project-bio\">\(esc(bio))</p>")
              <div class="chips">\(techStack)</div>
              \(stats)
              \(link)
            </div>
            """
    }

    private static func esc(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let css = """
        @page { size: letter; margin: 0.7in; }
        body {
          font-family: -apple-system, Helvetica, Arial, sans-serif;
          color: #1a1a1a;
          font-size: 13px;
          line-height: 1.5;
        }
        .header { display: flex; align-items: center; gap: 16px; margin-bottom: 24px; }
        .avatar { width: 64px; height: 64px; border-radius: 50%; object-fit: cover; }
        h1 { font-size: 24px; margin: 0; }
        .tagline { font-size: 13px; color: #666; font-weight: 600; margin-top: 2px; }
        .bio { margin: 8px 0 4px; }
        .links { margin-top: 4px; }
        .link-chip {
          display: inline-block; font-size: 11px; color: #0a5cff; text-decoration: none;
          margin-right: 10px;
        }
        .section { margin-top: 22px; }
        h2 {
          font-size: 15px; text-transform: uppercase; letter-spacing: 0.06em; color: #444;
          border-bottom: 1px solid #ddd; padding-bottom: 6px; margin-bottom: 12px;
        }
        .chips { margin-top: 6px; }
        .skill-chip, .tech-chip {
          display: inline-block; font-size: 11px; background: #f0f0f0; color: #333;
          border-radius: 10px; padding: 3px 9px; margin: 2px 4px 2px 0;
        }
        .achievement { margin-top: 10px; font-size: 12px; color: #8a6d00; }
        .project-card { margin-bottom: 16px; page-break-inside: avoid; }
        .project-title-row { display: flex; align-items: baseline; gap: 8px; }
        .project-name { font-size: 15px; font-weight: 700; }
        .status-chip {
          font-size: 10px; text-transform: uppercase; color: #666; background: #eee;
          border-radius: 8px; padding: 2px 7px;
        }
        .project-bio { margin: 4px 0; }
        .stats { font-size: 11px; color: #666; margin-top: 4px; }
        .project-link { font-size: 11px; color: #0a5cff; text-decoration: none; }
        .footer { margin-top: 30px; font-size: 10px; color: #999; text-align: center; }
        """
}
