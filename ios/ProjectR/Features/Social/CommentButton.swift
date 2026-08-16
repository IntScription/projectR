import SwiftUI

/// Icon + count that opens `CommentsSection` as an Instagram-style
/// half-height drawer instead of an always-inline block on the page.
struct CommentButton: View {
    let target: CommentsSection.Target
    /// Same idea as `LikeButton.preloaded` — skip the per-card fetch when
    /// the caller (a feed card backed by `project_feed`) already has the
    /// count.
    var preloadedCount: Int?

    @State private var commentCount = 0
    @State private var isPresentingSheet = false

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

    var body: some View {
        Button {
            isPresentingSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "bubble.right")
                if commentCount > 1 {
                    Text("\(commentCount)")
                }
            }
            .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Comments")
        .accessibilityValue(commentCount > 0 ? "\(commentCount)" : "")
        .task {
            if let preloadedCount {
                commentCount = preloadedCount
            } else {
                await refresh()
            }
        }
        .sheet(isPresented: $isPresentingSheet) {
            CommentsSection(target: target) { commentCount = $0 }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func refresh() async {
        commentCount = (try? await Engagement.count(table: "comments", filters: [targetColumn: targetID])) ?? 0
    }
}
