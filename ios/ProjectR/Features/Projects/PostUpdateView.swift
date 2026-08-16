import PhotosUI
import Supabase
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Posting an update is the retention loop — it's what makes a project a
/// living thing instead of a one-time portfolio entry. Only reachable from
/// ProjectDetailView when the signed-in user owns the project; RLS enforces
/// the same rule server-side regardless.
struct PostUpdateView: View {
    let projectID: UUID
    /// The storage path prefix for any attached media — must be the
    /// *uploader's* own id (storage RLS requires the path's first segment
    /// to equal `auth.uid()`), not necessarily the project's owner, since
    /// collaborators can post updates too.
    let uploaderID: UUID
    var onPosted: ((ProjectUpdate) -> Void)?

    @Environment(\.dismiss) private var dismiss

    private enum MediaKind {
        case image, video
    }

    @State private var text = ""
    @State private var selectedMedia: PhotosPickerItem?
    @State private var mediaData: Data?
    @State private var mediaKind: MediaKind?
    @State private var isPresentingPicker = false
    @State private var hasOfferedPickerOnce = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                mediaSection
                Section {
                    TextField("What did you ship?", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Post update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Post") { Task { await save() } }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .photosPicker(
                isPresented: $isPresentingPicker, selection: $selectedMedia,
                matching: .any(of: [.images, .videos]))
            .task {
                guard !hasOfferedPickerOnce else { return }
                hasOfferedPickerOnce = true
                try? await Task.sleep(for: .milliseconds(300))
                isPresentingPicker = true
            }
            .task(id: selectedMedia) {
                guard let selectedMedia else { return }
                mediaKind =
                    selectedMedia.supportedContentTypes.contains(where: { $0.conforms(to: .movie) })
                    ? .video : .image
                mediaData = try? await selectedMedia.loadTransferable(type: Data.self)
            }
        }
    }

    /// Media leads the form (Instagram's create pattern), auto-offered once
    /// on appear — but skippable, since not every update has a photo/clip.
    @ViewBuilder
    private var mediaSection: some View {
        Section {
            Button {
                isPresentingPicker = true
            } label: {
                if mediaKind == .image, let mediaData, let uiImage = UIImage(data: mediaData) {
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
                } else if mediaKind == .video {
                    VStack(spacing: 8) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.accentColor)
                        Text("Video attached")
                            .font(.subheadline.weight(.medium))
                        Text("Tap to choose a different clip.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.accentColor)
                        Text("Attach a photo or clip")
                            .font(.subheadline.weight(.medium))
                        Text("Optional — you can post a text-only update too.")
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

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let client = SupabaseManager.shared.client
            let newUpdate = NewProjectUpdate(
                projectID: projectID,
                body: text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let created: ProjectUpdate =
                try await client
                .from("project_updates")
                .insert(newUpdate)
                .select()
                .single()
                .execute()
                .value

            if let mediaData, let mediaKind {
                let isVideo = mediaKind == .video
                let ext = isVideo ? "mp4" : "jpg"
                let contentType = isVideo ? "video/mp4" : "image/jpeg"
                let path = "\(uploaderID)/\(created.id.uuidString).\(ext)"
                let storage = client.storage.from(SupabaseBucket.projectMedia)
                try await storage.upload(path, data: mediaData, options: FileOptions(contentType: contentType))
                let url = try storage.getPublicURL(path: path).absoluteString
                try await client
                    .from("update_media")
                    .insert(
                        NewUpdateMedia(
                            updateID: created.id, type: isVideo ? "video" : "image", url: url,
                            position: 0)
                    )
                    .execute()
            }

            onPosted?(created)
            dismiss()
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}

private struct NewProjectUpdate: Encodable {
    let projectID: UUID
    let body: String

    enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case body
    }
}

private struct NewUpdateMedia: Encodable {
    let updateID: UUID
    let type: String
    let url: String
    let position: Int

    enum CodingKeys: String, CodingKey {
        case updateID = "update_id"
        case type, url, position
    }
}
