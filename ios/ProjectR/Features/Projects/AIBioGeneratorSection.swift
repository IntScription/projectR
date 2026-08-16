import Supabase
import SwiftUI

/// Shared between `CreateProjectView` and `EditProjectView` — a reviewable
/// AI-generated portfolio bio, kept separate from the project's own
/// `description` field. Generation is always an explicit tap, and the
/// result is always editable before it's saved: nothing this produces
/// reaches `Project.aiSummary` (and therefore a portfolio PDF) unseen.
struct AIBioGeneratorSection: View {
    @Binding var aiSummary: String
    let name: String
    let category: ProjectCategory
    let status: ProjectStatus
    let tags: [String]
    let techStack: [String]
    let description: String
    /// Re-fetched here (rather than threaded from the parent's own GitHub
    /// enrichment) so this component stays self-contained — only costs an
    /// extra network call on the explicit "Generate" tap, not on every
    /// keystroke the way the parent's own enrichment does.
    let githubURL: String

    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if aiSummary.isEmpty {
                generateButton(title: "Generate bio with AI", systemImage: "sparkles")
            } else {
                TextField("Portfolio bio", text: $aiSummary, axis: .vertical)
                    .lineLimit(3...8)
                generateButton(title: "Regenerate", systemImage: "arrow.clockwise")
                Button(role: .destructive) {
                    aiSummary = ""
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Portfolio Bio")
        } footer: {
            Text(
                "A short, factual summary used in your Portfolio PDF (Settings → Portfolio). Review and edit it before saving — nothing generated here is used until you do."
            )
        }
    }

    private func generateButton(title: String, systemImage: String) -> some View {
        Button {
            Task { await generate() }
        } label: {
            if isGenerating {
                HStack { ProgressView(); Text("Generating…") }
            } else {
                Label(title, systemImage: systemImage)
            }
        }
        .disabled(isGenerating || name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func generate() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            let trimmedGitHubURL = githubURL.trimmingCharacters(in: .whitespaces)
            let repoDescription =
                trimmedGitHubURL.isEmpty
                ? nil : await GitHubService.publicMetadata(githubURL: trimmedGitHubURL)?.description
            aiSummary = try await ProjectBioGenerator.generate(
                name: name, category: category.rawValue, status: status.rawValue, tags: tags,
                techStack: techStack, description: description.isEmpty ? nil : description,
                repoDescription: repoDescription)
            AnalyticsService.track(
                "ai_bio_generated",
                properties: ["tier": .string(ProjectBioGenerator.isOnDeviceAvailable ? "on_device" : "server")])
        } catch {
            CrashReporter.capture(error, context: "generate_ai_bio")
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}
