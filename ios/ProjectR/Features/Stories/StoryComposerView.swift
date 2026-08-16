import Supabase
import SwiftUI

/// The post-capture screen — full-bleed preview, an optional "also save to
/// a highlight" pick, and a single post action. Deliberately no caption/
/// text-overlay field: stories are straight photo/video, not a mini editor
/// (draggable text layers are a real standalone feature, out of scope here).
struct StoryComposerView: View {
    let uploaderID: UUID
    let mediaData: Data
    let mediaKind: StoryMediaKind
    var onPosted: (() -> Void)?

    @State private var isPosting = false
    @State private var errorMessage: String?
    @State private var selectedHighlight: StoryHighlight?
    @State private var isPresentingHighlightPicker = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            preview
            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
        .sheet(isPresented: $isPresentingHighlightPicker) {
            HighlightPickerSheet(ownerID: uploaderID) { highlight in
                selectedHighlight = highlight
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch mediaKind {
        case .image:
            if let uiImage = UIImage(data: mediaData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            }
        case .video:
            VStack(spacing: 12) {
                Image(systemName: "video.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                Text("Video ready to post")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .accessibilityLabel("Cancel")
            Spacer()
        }
        .padding()
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
            Button {
                isPresentingHighlightPicker = true
            } label: {
                Label(
                    selectedHighlight.map { "Saving to \($0.title)" } ?? "Also save to a highlight",
                    systemImage: "star"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.white.opacity(0.15), in: Capsule())
            }
            Button {
                Task { await post() }
            } label: {
                Group {
                    if isPosting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Post to your story").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .foregroundStyle(.black)
            .background(.white, in: Capsule())
            .disabled(isPosting)
        }
        .padding()
        .padding(.bottom, 20)
    }

    private func post() async {
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }
        do {
            let client = SupabaseManager.shared.client
            let storyID = UUID()
            let ext = mediaKind == .video ? "mp4" : "jpg"
            let contentType = mediaKind == .video ? "video/mp4" : "image/jpeg"
            let path = "\(uploaderID)/stories/\(storyID.uuidString).\(ext)"
            let storage = client.storage.from(SupabaseBucket.projectMedia)
            try await storage.upload(path, data: mediaData, options: FileOptions(contentType: contentType))
            let url = try storage.getPublicURL(path: path).absoluteString

            let created: Story =
                try await client
                .from("stories")
                .insert(
                    NewStory(id: storyID, authorID: uploaderID, mediaURL: url, mediaType: mediaKind.rawValue)
                )
                .select()
                .single()
                .execute()
                .value

            if let selectedHighlight {
                try await client
                    .from("story_highlight_items")
                    .insert(NewHighlightItem(highlightID: selectedHighlight.id, storyID: created.id))
                    .execute()
            }

            onPosted?()
            dismiss()
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}

private struct NewStory: Encodable {
    let id: UUID
    let authorID: UUID
    let mediaURL: String
    let mediaType: String

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case mediaURL = "media_url"
        case mediaType = "media_type"
    }
}

private struct NewHighlightItem: Encodable {
    let highlightID: UUID
    let storyID: UUID

    enum CodingKeys: String, CodingKey {
        case highlightID = "highlight_id"
        case storyID = "story_id"
    }
}
