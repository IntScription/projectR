import PhotosUI
import Supabase
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Owner-only. Exists so a project skipped past the cover-photo prompt (or
/// created with just a name and nothing else) doesn't stay a blank banner
/// forever — everything that can be set at creation can be changed here
/// too, including replacing the photo.
struct EditProjectView: View {
    let project: Project
    var onSaved: ((Project) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var description: String
    @State private var aiSummary: String
    @State private var category: ProjectCategory
    @State private var status: ProjectStatus
    @State private var tagsText: String
    @State private var techStack: [String]
    @State private var githubURL: String
    @State private var links: [ProfileLink]
    @State private var isOpenSource: Bool

    @State private var existingCoverImageURL: String?
    @State private var existingCoverVideoURL: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var coverImageData: Data?
    @State private var coverVideoData: Data?
    @State private var isPresentingPicker = false
    @State private var isEnriching = false

    @State private var isSaving = false
    @State private var errorMessage: String?

    init(project: Project, onSaved: ((Project) -> Void)? = nil) {
        self.project = project
        self.onSaved = onSaved
        _name = State(initialValue: project.name)
        _description = State(initialValue: project.description ?? "")
        _aiSummary = State(initialValue: project.aiSummary ?? "")
        _category = State(initialValue: project.category)
        _status = State(initialValue: project.status)
        _tagsText = State(initialValue: project.tags.joined(separator: ", "))
        _techStack = State(initialValue: project.techStack)
        _githubURL = State(initialValue: project.githubURL ?? "")
        _links = State(initialValue: project.links)
        _isOpenSource = State(initialValue: project.isOpenSource)
        _existingCoverImageURL = State(initialValue: project.coverImageURL)
        _existingCoverVideoURL = State(initialValue: project.coverVideoURL)
    }

    var body: some View {
        Form {
            coverImageSection
            basicsSection
            AIBioGeneratorSection(
                aiSummary: $aiSummary, name: name, category: category, status: status,
                tags: Self.split(tagsText), techStack: techStack, description: description,
                githubURL: githubURL)
            linksSection
            tagsSection
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle("Edit project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .photosPicker(
            isPresented: $isPresentingPicker, selection: $selectedPhoto,
            matching: .any(of: [.images, .videos])
        )
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            let isVideo = selectedPhoto.supportedContentTypes.contains { $0.conforms(to: .movie) }
            let data = try? await selectedPhoto.loadTransferable(type: Data.self)
            if isVideo {
                coverVideoData = data
                coverImageData = nil
            } else {
                coverImageData = data
                coverVideoData = nil
            }
        }
        .task(id: githubURL) { await enrichFromGitHub() }
    }

    private func enrichFromGitHub() async {
        let trimmed = githubURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != project.githubURL else { return }
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }

        isEnriching = true
        defer { isEnriching = false }
        guard let repo = await GitHubService.publicMetadata(githubURL: trimmed) else { return }
        guard !Task.isCancelled else { return }

        if description.trimmingCharacters(in: .whitespaces).isEmpty, let repoDescription = repo.description {
            description = repoDescription
        }
        for language in await GitHubService.languages(githubURL: trimmed) where !techStack.contains(language) {
            techStack.append(language)
        }
        if tagsText.trimmingCharacters(in: .whitespaces).isEmpty, !repo.topics.isEmpty {
            tagsText = repo.topics.joined(separator: ", ")
        }
    }

    @ViewBuilder
    private var basicsSection: some View {
        Section("Basics") {
            TextField("Name", text: $name)
            TextField("Description", text: $description, axis: .vertical)
                .lineLimit(3...6)
            Picker("Category", selection: $category) {
                ForEach(ProjectCategory.allCases) { Text($0.rawValue.capitalized).tag($0) }
            }
            Picker("Status", selection: $status) {
                ForEach(ProjectStatus.allCases) { Text($0.rawValue.capitalized).tag($0) }
            }
        }
    }

    @ViewBuilder
    private var coverImageSection: some View {
        Section {
            Button {
                isPresentingPicker = true
            } label: {
                if let coverImageData, let uiImage = UIImage(data: coverImageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(alignment: .bottomTrailing) { changeBadge }
                } else if let url = existingCoverImageURL.flatMap(URL.init) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color(.tertiarySystemFill)
                    }
                    .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .bottomTrailing) { changeBadge }
                } else if coverVideoData != nil || existingCoverVideoURL != nil {
                    VStack(spacing: 8) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.accentColor)
                        Text("Video selected")
                            .font(.subheadline.weight(.medium))
                        Text("It'll autoplay muted in the feed. Tap to change.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.accentColor)
                        Text("Add a cover photo or video")
                            .font(.subheadline.weight(.medium))
                        Text("Projects with a cover get noticed more.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var changeBadge: some View {
        Label("Change", systemImage: "photo.badge.arrow.down")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
            .padding(10)
    }

    @ViewBuilder
    private var tagsSection: some View {
        Section {
            TextField("Tags", text: $tagsText)
            TechStackEditor(techStack: $techStack)
        } header: {
            Text("Tags & tech (optional)")
        } footer: {
            Text(
                "Skip this entirely if you want — add a GitHub link above and ProjectR figures out the tech stack on its own. Tags are comma-separated; tech chips are for anything auto-detection can't see, like a framework."
            )
        }
    }

    @ViewBuilder
    private var linksSection: some View {
        Section {
            HStack {
                TextField("GitHub URL", text: $githubURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if isEnriching {
                    ProgressView()
                }
            }
            if !githubURL.trimmingCharacters(in: .whitespaces).isEmpty {
                Toggle("Open source", isOn: $isOpenSource)
            }
            ProjectLinksEditor(links: $links)
        } header: {
            Text("Links")
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let coverImageURL = try await uploadCoverImageIfNeeded()
            let coverVideoURL = try await uploadCoverVideoIfNeeded()

            let update = ProjectUpdatePayload(
                name: name.trimmingCharacters(in: .whitespaces),
                description: description.isEmpty ? nil : description,
                aiSummary: aiSummary.isEmpty ? nil : aiSummary,
                coverImageURL: coverVideoURL != nil ? nil : (coverImageURL ?? existingCoverImageURL),
                coverVideoURL: coverImageURL != nil ? nil : (coverVideoURL ?? existingCoverVideoURL),
                category: category,
                tags: Self.split(tagsText),
                status: status,
                techStack: techStack,
                githubURL: githubURL.isEmpty ? nil : githubURL,
                links: links.filter { !$0.url.trimmingCharacters(in: .whitespaces).isEmpty },
                isOpenSource: githubURL.isEmpty ? false : isOpenSource
            )

            let saved: Project =
                try await SupabaseManager.shared.client
                .from("projects")
                .update(update)
                .eq("id", value: project.id)
                .select()
                .single()
                .execute()
                .value

            onSaved?(saved)
            dismiss()
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func uploadCoverImageIfNeeded() async throws -> String? {
        guard let coverImageData else { return nil }
        let path = "\(project.ownerID)/\(project.id.uuidString).jpg"
        let storage = SupabaseManager.shared.client.storage.from(SupabaseBucket.projectMedia)
        try await storage.upload(
            path, data: coverImageData, options: FileOptions(contentType: "image/jpeg", upsert: true))
        return try storage.getPublicURL(path: path).absoluteString
            + "?v=\(Int(Date().timeIntervalSince1970))"
    }

    private func uploadCoverVideoIfNeeded() async throws -> String? {
        guard let coverVideoData else { return nil }
        let path = "\(project.ownerID)/\(project.id.uuidString).mov"
        let storage = SupabaseManager.shared.client.storage.from(SupabaseBucket.projectMedia)
        try await storage.upload(
            path, data: coverVideoData, options: FileOptions(contentType: "video/quicktime", upsert: true))
        return try storage.getPublicURL(path: path).absoluteString
            + "?v=\(Int(Date().timeIntervalSince1970))"
    }

    private static func split(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

private struct ProjectUpdatePayload: Encodable {
    let name: String
    let description: String?
    let aiSummary: String?
    let coverImageURL: String?
    let coverVideoURL: String?
    let category: ProjectCategory
    let tags: [String]
    let status: ProjectStatus
    let techStack: [String]
    let githubURL: String?
    let links: [ProfileLink]
    let isOpenSource: Bool

    enum CodingKeys: String, CodingKey {
        case name, description
        case aiSummary = "ai_summary"
        case coverImageURL = "cover_image_url"
        case coverVideoURL = "cover_video_url"
        case category, tags, status
        case techStack = "tech_stack"
        case githubURL = "github_url"
        case links
        case isOpenSource = "is_open_source"
    }
}
