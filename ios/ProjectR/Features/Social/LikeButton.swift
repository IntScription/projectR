import SwiftUI

struct LikeButton: View {
    enum Target: Hashable {
        case project(UUID)
        case update(UUID)
    }

    let target: Target
    /// When the caller already knows the like state (e.g. a feed card
    /// backed by `project_feed`, which now carries `is_liked_by_me`
    /// itself), pass it here to skip the network round trip every card
    /// would otherwise make on appear. `nil` (the default, `ProjectDetailView`'s
    /// standalone usage) falls back to fetching it live.
    var preloaded: (isLiked: Bool, count: Int)?

    @State private var isLiked = false
    @State private var likeCount = 0
    @State private var isLoading = false

    private var currentUserID: UUID? {
        SupabaseManager.shared.client.auth.currentSession?.user.id
    }

    private var targetColumn: String {
        switch target {
        case .project: "project_id"
        case .update: "update_id"
        }
    }

    private var targetID: UUID {
        switch target {
        case .project(let id), .update(let id): id
        }
    }

    @State private var isPopping = false

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .scaleEffect(isPopping ? 1.35 : 1)
                if likeCount > 1 {
                    Text("\(likeCount)")
                }
            }
            // `.tint()` doesn't reliably recolor a plain `Image` — it's
            // meant for control chrome, not content — and a `.foregroundStyle`
            // set by an ancestor (e.g. a feed card's engagement row) would
            // otherwise win over it regardless. Setting `.foregroundStyle`
            // here, on the label itself, is what actually makes the heart
            // turn red and stay red no matter what a parent view does.
            .foregroundStyle(isLiked ? Color.red : Color.secondary)
        }
        .disabled(isLoading)
        .accessibilityLabel(isLiked ? "Liked" : "Like")
        .accessibilityValue(likeCount > 0 ? "\(likeCount)" : "")
        .task {
            if let preloaded {
                isLiked = preloaded.isLiked
                likeCount = preloaded.count
            } else {
                await refresh()
            }
        }
    }

    private func refresh() async {
        async let countTask = Engagement.count(table: "likes", filters: [targetColumn: targetID])
        if let currentUserID {
            isLiked =
                (try? await Engagement.exists(
                    table: "likes",
                    filters: ["user_id": currentUserID, targetColumn: targetID]
                )) ?? false
        }
        likeCount = (try? await countTask) ?? 0
    }

    private func toggle() async {
        guard let currentUserID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if isLiked {
                try await Engagement.remove(
                    table: "likes",
                    filters: ["user_id": currentUserID, targetColumn: targetID]
                )
                isLiked = false
                likeCount = max(0, likeCount - 1)
            } else {
                try await Engagement.insert(
                    table: "likes",
                    values: ["user_id": currentUserID, targetColumn: targetID]
                )
                isLiked = true
                likeCount += 1
                withAnimation(.spring(duration: 0.3, bounce: 0.6)) { isPopping = true }
                withAnimation(.spring(duration: 0.25).delay(0.15)) { isPopping = false }
            }
        } catch {
            // Best-effort toggle — a failed request just leaves state unchanged,
            // but still worth a trace in production logs.
            AppLogger.network.error("Like toggle failed: \(error.localizedDescription)")
        }
    }
}
