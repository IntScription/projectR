import FoundationModels
import Foundation
import Supabase

/// Two-tier AI project-bio generation. Preferred tier is fully on-device
/// via Apple's `FoundationModels` framework — free, private, no network —
/// used whenever `SystemLanguageModel.default.availability` reports
/// `.available` (Apple-Intelligence-eligible hardware, iOS 26+, the
/// feature enabled in Settings). Everyone else falls through to the
/// `generate-project-bio` Edge Function, which calls the Anthropic API
/// server-side. Same prompt, same output shape, either way — the tier is
/// invisible to the caller.
///
/// Never writes anything itself: the caller shows the result for review
/// and only persists it to `Project.aiSummary` on explicit save, so
/// nothing generated here reaches a portfolio PDF unseen.
enum ProjectBioGenerator {
    static var isOnDeviceAvailable: Bool {
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        return false
    }

    static func generate(
        name: String, category: String, status: String, tags: [String], techStack: [String],
        description: String?, repoDescription: String?
    ) async throws -> String {
        if #available(iOS 26.0, *), SystemLanguageModel.default.availability == .available {
            return try await generateOnDevice(
                name: name, category: category, status: status, tags: tags, techStack: techStack,
                description: description, repoDescription: repoDescription)
        }
        return try await generateViaEdgeFunction(
            name: name, category: category, status: status, tags: tags, techStack: techStack,
            description: description, repoDescription: repoDescription)
    }

    @available(iOS 26.0, *)
    private static func generateOnDevice(
        name: String, category: String, status: String, tags: [String], techStack: [String],
        description: String?, repoDescription: String?
    ) async throws -> String {
        let session = LanguageModelSession(
            instructions:
                "You write short, factual project bios for developer portfolios. Write 2-3 " +
                "sentences covering what the project is and its real tech stack, based strictly " +
                "on the facts given. Never invent metrics, claims, or details not present in the " +
                "facts. No marketing language, no emoji, no headings — plain prose only.")
        let projectFacts = facts(
            name: name, category: category, status: status, tags: tags, techStack: techStack,
            description: description, repoDescription: repoDescription)
        let prompt = "Project facts:\n\(projectFacts)"
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func generateViaEdgeFunction(
        name: String, category: String, status: String, tags: [String], techStack: [String],
        description: String?, repoDescription: String?
    ) async throws -> String {
        let requestBody = EdgeFunctionRequest(
            name: name, category: category, status: status, tags: tags, techStack: techStack,
            description: description, repoDescription: repoDescription)
        let response: EdgeFunctionResponse = try await SupabaseManager.shared.client.functions.invoke(
            "generate-project-bio", options: FunctionInvokeOptions(body: requestBody))
        return response.bio
    }

    private static func facts(
        name: String, category: String, status: String, tags: [String], techStack: [String],
        description: String?, repoDescription: String?
    ) -> String {
        var lines = ["Name: \(name)", "Category: \(category)", "Status: \(status)"]
        if !techStack.isEmpty { lines.append("Tech stack: \(techStack.joined(separator: ", "))") }
        if !tags.isEmpty { lines.append("Tags: \(tags.joined(separator: ", "))") }
        if let description, !description.isEmpty {
            lines.append("Existing description (from the creator): \(description)")
        }
        if let repoDescription, !repoDescription.isEmpty {
            lines.append("GitHub repository description: \(repoDescription)")
        }
        return lines.joined(separator: "\n")
    }

    private struct EdgeFunctionRequest: Encodable {
        var name: String
        var category: String
        var status: String
        var tags: [String]
        var techStack: [String]
        var description: String?
        var repoDescription: String?
    }

    private struct EdgeFunctionResponse: Decodable {
        var bio: String
    }
}
