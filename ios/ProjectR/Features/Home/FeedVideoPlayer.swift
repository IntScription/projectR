import AVFoundation
import SwiftUI

/// Autoplaying, looping, muted-by-default video preview for feed cards —
/// Instagram/TikTok style, not AVKit's `VideoPlayer` (which always draws
/// its own play/pause/scrubber chrome on top). A raw `AVPlayerLayer`
/// gives a chrome-free surface; tapping it toggles sound and briefly
/// shows a speaker icon confirming the new state, then fades out — the
/// icon is never on screen unless you just tapped.
struct FeedVideoPlayer: View {
    let url: URL

    @State private var queuePlayer: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var isMuted = true
    @State private var showMuteIcon = false
    @State private var hideIconTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Always present, not just a fallback for "no player yet" — an
            // `AVPlayerLayer` has no fill of its own before its first
            // frame decodes, so without this the card would flash through
            // to whatever's behind it (white) for however long buffering
            // takes, instead of a clean black video slot the whole time.
            Color.black
            if let queuePlayer {
                PlayerLayerView(player: queuePlayer)
            }

            if showMuteIcon {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(.black.opacity(0.45), in: Circle())
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggleMute() }
        .onAppear { setUpPlayerIfNeeded() }
        .onDisappear { queuePlayer?.pause() }
        .accessibilityLabel("Video")
        .accessibilityHint(isMuted ? "Double-tap to unmute" : "Double-tap to mute")
        .accessibilityAddTraits(.isButton)
    }

    private func setUpPlayerIfNeeded() {
        if let queuePlayer {
            queuePlayer.play()
            return
        }
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.play()
        queuePlayer = player
    }

    private func toggleMute() {
        isMuted.toggle()
        queuePlayer?.isMuted = isMuted

        hideIconTask?.cancel()
        withAnimation(.spring(duration: 0.25)) { showMuteIcon = true }
        hideIconTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { showMuteIcon = false }
        }
    }
}

/// Chrome-free video surface — `AVPlayerLayer` directly, not AVKit's
/// `VideoPlayer`, so nothing but the picture itself ever renders. Not
/// `private` — `StoryViewerView` reuses it for a plain (non-looping)
/// `AVPlayer` too, since both just need a bare player layer.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> ContainerView {
        let view = ContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: ContainerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class ContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
