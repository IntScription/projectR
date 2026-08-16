import PhotosUI
import Supabase
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CreateProjectView: View {
    let ownerID: UUID
    var onCreated: ((Project) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var aiSummary = ""
    @State private var category: ProjectCategory = .software
    @State private var status: ProjectStatus = .idea
    @State private var tagsText = ""
    /// Seeded from the GitHub URL's real language breakdown (see
    /// `enrichFromGitHub`), then freely editable via `TechStackEditor` —
    /// language detection alone can't see frameworks like React Native.
    @State private var techStack: [String] = []
    @State private var githubURL = ""
    @State private var links: [ProfileLink] = []
    @State private var isOpenSource = false

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var coverImageData: Data?
    @State private var coverVideoData: Data?
    @State private var isPresentingPicker = false
    @State private var isEnriching = false

    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var isGitHubConnected = false
    @State private var isPresentingGitHubImport = false

    var body: some View {
        Form {
            if isGitHubConnected {
                Section {
                    Button {
                        isPresentingGitHubImport = true
                    } label: {
                        Label("Import from GitHub", systemImage: "arrow.triangle.branch")
                    }
                } footer: {
                    Text("Prefill this form from one of your repos instead of typing everything by hand.")
                }
            }
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
        .navigationTitle("New project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Create") { Task { await save() } }
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
        .task { isGitHubConnected = await GitHubService.isConnected() }
        .task(id: githubURL) { await enrichFromGitHub() }
        .sheet(isPresented: $isPresentingGitHubImport) {
            GitHubImportSheet { repo in
                importFrom(repo)
            }
        }
    }

    private func importFrom(_ repo: GitHubRepo) {
        name = repo.name
        if let description = repo.description { self.description = description }
        if let language = repo.language, !techStack.contains(language) {
            techStack.append(language)
        }
        if tagsText.isEmpty, !repo.topics.isEmpty {
            tagsText = repo.topics.joined(separator: ", ")
        }
        githubURL = repo.htmlURL
        isOpenSource = !repo.isPrivate

        // The primary language above is instant; the full breakdown needs
        // a second API call, so it fills in a moment later.
        Task {
            for language in await GitHubService.languages(githubURL: repo.htmlURL) where !techStack.contains(language) {
                techStack.append(language)
            }
        }
    }

    /// Fires on every keystroke via `.task(id:)`, but each run starts by
    /// sleeping — SwiftUI cancels the in-flight task the moment `githubURL`
    /// changes again, so only the run after typing actually pauses reaches
    /// the network call. Never overwrites anything the user already typed;
    /// only fills fields that are still empty.
    private func enrichFromGitHub() async {
        let trimmed = githubURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
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
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = repo.name
        }
        isOpenSource = !repo.isPrivate
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

    /// Media-first: the cover photo/video leads the form (Instagram's
    /// create pattern) as a single always-visible tap target — no
    /// separate auto-popping picker on top of it, since that was just a
    /// second way to trigger the same thing. Skippable, since cover media
    /// isn't required to create a project. Videos autoplay muted in the
    /// Home/Discover feed once published; this form just confirms one was
    /// picked rather than rendering a live preview.
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
                        .overlay(alignment: .bottomTrailing) {
                            Label("Change", systemImage: "photo.badge.arrow.down")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.55), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(10)
                        }
                } else if coverVideoData != nil {
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
                        Text("Optional, but projects with a cover get noticed more.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .buttonStyle(.plain)
        }
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
        } footer: {
            Text(
                githubURL.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "Paste a GitHub URL and ProjectR fills in the description, tags, and tech stack from the real repo."
                    : "Open source projects show a Download button that forks this repo to a viewer's own GitHub account."
            )
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let coverImageURL = try await uploadCoverImageIfNeeded()
            let coverVideoURL = try await uploadCoverVideoIfNeeded()

            let newProject = NewProject(
                ownerID: ownerID,
                slug: Self.slug(from: name),
                name: name.trimmingCharacters(in: .whitespaces),
                description: description.isEmpty ? nil : description,
                aiSummary: aiSummary.isEmpty ? nil : aiSummary,
                coverImageURL: coverImageURL,
                coverVideoURL: coverVideoURL,
                category: category,
                tags: Self.split(tagsText),
                status: status,
                techStack: techStack,
                githubURL: githubURL.isEmpty ? nil : githubURL,
                links: links.filter { !$0.url.trimmingCharacters(in: .whitespaces).isEmpty },
                isOpenSource: githubURL.isEmpty ? false : isOpenSource
            )

            let created: Project =
                try await SupabaseManager.shared.client
                .from("projects")
                .insert(newProject)
                .select()
                .single()
                .execute()
                .value

            AnalyticsService.track(
                "project_created",
                properties: [
                    "category": .string(category.rawValue),
                    "has_github_url": .bool(!githubURL.isEmpty),
                ])
            onCreated?(created)
            dismiss()
        } catch {
            CrashReporter.capture(error, context: "create_project")
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func uploadCoverImageIfNeeded() async throws -> String? {
        guard let coverImageData else { return nil }
        let path = "\(ownerID)/\(UUID().uuidString).jpg"
        let storage = SupabaseManager.shared.client.storage.from(SupabaseBucket.projectMedia)
        try await storage.upload(
            path, data: coverImageData, options: FileOptions(contentType: "image/jpeg"))
        return try storage.getPublicURL(path: path).absoluteString
    }

    private func uploadCoverVideoIfNeeded() async throws -> String? {
        guard let coverVideoData else { return nil }
        let path = "\(ownerID)/\(UUID().uuidString).mov"
        let storage = SupabaseManager.shared.client.storage.from(SupabaseBucket.projectMedia)
        try await storage.upload(
            path, data: coverVideoData, options: FileOptions(contentType: "video/quicktime"))
        return try storage.getPublicURL(path: path).absoluteString
    }

    private static func slug(from name: String) -> String {
        let lowered = name.lowercased()
        let dashed = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(dashed)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        let suffix = UUID().uuidString.prefix(6).lowercased()
        return collapsed.isEmpty ? "project-\(suffix)" : "\(collapsed)-\(suffix)"
    }

    private static func split(_ text: String) -> [String] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

private struct NewProject: Encodable {
    let ownerID: UUID
    let slug: String
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
        case ownerID = "owner_id"
        case slug, name, description
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
