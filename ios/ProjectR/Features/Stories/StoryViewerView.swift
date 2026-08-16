import AVFoundation
import SwiftUI

/// Full-screen story viewer for one author's ordered set of stories.
/// Segmented progress bar auto-advances (fixed duration for images, real
/// clip duration for video), tap left-third/right-two-thirds to step
/// back/forward, long-press to pause. Two ways to close, deliberately: the
/// X top-left (the explicit ask for this screen) and swipe-down, which
/// stays consistent with the swipe-to-dismiss convention used everywhere
/// else in the app (comments, share) — both are standard on Instagram's
/// own viewer, so there's no real conflict between them.
struct StoryViewerView: View {
    let stories: [Story]
    let startIndex: Int
    let authorID: UUID
    let authorUsername: String
    let authorDisplayName: String
    let authorAvatarURL: String?
    let isOwnStory: Bool
    var onDeleted: ((UUID) -> Void)?

    @State private var currentIndex: Int
    @State private var progress: Double = 0
    @State private var isPaused = false
    @State private var player: AVPlayer?
    @State private var isPresentingShare = false
    @State private var isPresentingHighlightPicker = false
    @State private var isPresentingReport = false
    @State private var isPresentingDeleteConfirm = false
    @State private var didDeleteStory = false
    @State private var dragOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss

    private static let imageDuration: Double = 5
    private static let fallbackVideoDuration: Double = 15
    private static let tickInterval: Double = 1.0 / 30

    init(
        stories: [Story], startIndex: Int, authorID: UUID, authorUsername: String,
        authorDisplayName: String, authorAvatarURL: String?, isOwnStory: Bool,
        onDeleted: ((UUID) -> Void)? = nil
    ) {
        self.stories = stories
        self.startIndex = startIndex
        self.authorID = authorID
        self.authorUsername = authorUsername
        self.authorDisplayName = authorDisplayName
        self.authorAvatarURL = authorAvatarURL
        self.isOwnStory = isOwnStory
        self.onDeleted = onDeleted
        _currentIndex = State(initialValue: startIndex)
    }

    private var currentStory: Story? {
        stories.indices.contains(currentIndex) ? stories[currentIndex] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let currentStory {
                media(for: currentStory)
            }
            tapZones
            VStack(spacing: 10) {
                progressBar
                header
                Spacer()
            }
            .padding(.top, 8)
        }
        .statusBarHidden()
        .offset(y: max(dragOffset, 0))
        .opacity(1 - min(dragOffset / 400, 0.6))
        .gesture(dismissDrag)
        .sheet(isPresented: $isPresentingShare) {
            if let currentStory, let url = URL(string: currentStory.mediaURL) {
                ActivityShareSheet(items: [url], onSendInApp: {})
            }
        }
        .sheet(isPresented: $isPresentingHighlightPicker) {
            HighlightPickerSheet(ownerID: authorID) { highlight in
                Task { await addCurrentStory(toHighlight: highlight) }
            }
        }
        .sheet(isPresented: $isPresentingReport) {
            if let currentStory {
                ReportSheet(targetType: .story, targetID: currentStory.id)
            }
        }
        .confirmationDialog(
            "Delete this story?", isPresented: $isPresentingDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await deleteCurrentStory() } }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: didDeleteStory) { _, newValue in newValue }
        .task(id: currentStory?.id) { await onSegmentStart() }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private func media(for story: Story) -> some View {
        switch story.mediaType {
        case .image:
            AsyncImage(url: URL(string: story.mediaURL)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView().tint(.white)
            }
        case .video:
            if let player {
                PlayerLayerView(player: player)
            } else {
                ProgressView().tint(.white)
            }
        }
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(stories.indices, id: \.self) { index in
                GeometryReader { proxy in
                    Capsule()
                        .fill(.white.opacity(0.3))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.white)
                                .frame(width: proxy.size.width * segmentFraction(for: index))
                        }
                }
                .frame(height: 2.5)
            }
        }
        .padding(.horizontal, 10)
    }

    private func segmentFraction(for index: Int) -> Double {
        if index < currentIndex { return 1 }
        if index == currentIndex { return progress }
        return 0
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(8)
            }
            .accessibilityLabel("Close")

            AsyncImage(url: authorAvatarURL.flatMap(URL.init)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(.white.opacity(0.25))
            }
            .frame(width: 30, height: 30)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 0) {
                Text(authorDisplayName).font(.subheadline.weight(.semibold))
                Text("@\(authorUsername)").font(.caption2)
            }
            .foregroundStyle(.white)

            Spacer()

            Menu {
                Button {
                    isPresentingShare = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                Button {
                    isPresentingHighlightPicker = true
                } label: {
                    Label("Add to Highlights", systemImage: "star")
                }
                if isOwnStory {
                    Button(role: .destructive) {
                        isPresentingDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } else {
                    Button(role: .destructive) {
                        isPresentingReport = true
                    } label: {
                        Label("Report", systemImage: "flag")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(8)
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 12)
    }

    /// Left third steps back (or restarts the very first story), right
    /// two-thirds steps forward (or dismisses after the last one). A
    /// long-press anywhere pauses without stepping.
    private var tapZones: some View {
        HStack(spacing: 0) {
            Color.clear.contentShape(Rectangle())
                .frame(maxWidth: .infinity)
                .onTapGesture { goToPrevious() }
            Color.clear.contentShape(Rectangle())
                .frame(maxWidth: .infinity)
                .onTapGesture { goToNext() }
        }
        .onLongPressGesture(minimumDuration: 0.15, maximumDistance: 40, pressing: { pressing in
            isPaused = pressing
            if pressing { player?.pause() } else { player?.play() }
        }, perform: {})
    }

    private var dismissDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard value.translation.height > 0 else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                if value.translation.height > 120 {
                    dismiss()
                } else {
                    withAnimation(.spring(duration: 0.3)) { dragOffset = 0 }
                }
            }
    }

    private func goToPrevious() {
        if currentIndex > 0 {
            currentIndex -= 1
        } else {
            progress = 0
        }
    }

    private func goToNext() {
        if currentIndex < stories.count - 1 {
            currentIndex += 1
        } else {
            dismiss()
        }
    }

    /// Records the view (skipped for your own story — nothing meaningful
    /// to track) and starts that segment's auto-advance timer, loading a
    /// video's real duration first rather than assuming a fixed length.
    private func onSegmentStart() async {
        progress = 0
        player = nil
        guard let currentStory else { return }

        if !isOwnStory {
            try? await SupabaseManager.shared.client
                .from("story_views")
                .upsert(["story_id": currentStory.id.uuidString, "viewer_id": authorID.uuidString])
                .execute()
        }

        let duration: Double
        if currentStory.mediaType == .video, let url = URL(string: currentStory.mediaURL) {
            let item = AVPlayerItem(url: url)
            let newPlayer = AVPlayer(playerItem: item)
            player = newPlayer
            newPlayer.play()
            let loadedSeconds = try? await AVURLAsset(url: url).load(.duration).seconds
            duration =
                (loadedSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }) ?? Self.fallbackVideoDuration
        } else {
            duration = Self.imageDuration
        }

        await runTimer(duration: duration, storyID: currentStory.id)
    }

    private func runTimer(duration: Double, storyID: UUID) async {
        while progress < 1 {
            guard currentStory?.id == storyID else { return }
            try? await Task.sleep(for: .seconds(Self.tickInterval))
            guard currentStory?.id == storyID else { return }
            if !isPaused {
                progress = min(progress + Self.tickInterval / duration, 1)
            }
        }
        guard currentStory?.id == storyID else { return }
        goToNext()
    }

    private func addCurrentStory(toHighlight highlight: StoryHighlight) async {
        guard let currentStory else { return }
        try? await SupabaseManager.shared.client
            .from("story_highlight_items")
            .upsert(["highlight_id": highlight.id.uuidString, "story_id": currentStory.id.uuidString])
            .execute()
    }

    private func deleteCurrentStory() async {
        guard let currentStory else { return }
        do {
            try await SupabaseManager.shared.client
                .from("stories")
                .delete()
                .eq("id", value: currentStory.id)
                .execute()
            // `stories` is a fixed snapshot for this viewing session — rather
            // than patch it locally and risk showing stale segments, just
            // close; `onDeleted` tells the caller to refresh its own data.
            didDeleteStory = true
            AnalyticsService.track("story_deleted")
            onDeleted?(currentStory.id)
            dismiss()
        } catch {
            CrashReporter.capture(error, context: "delete_story")
            AppLogger.stories.error("Failed to delete story: \(error.localizedDescription)")
        }
    }
}
