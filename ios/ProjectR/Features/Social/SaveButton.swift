import SwiftUI

/// Saves are private bookmarks (see the migration's RLS note), so unlike
/// Follow/Like there's no count to show here.
struct SaveButton: View {
    let projectID: UUID

    @State private var isSaved = false
    @State private var isLoading = false

    private var currentUserID: UUID? {
        SupabaseManager.shared.client.auth.currentSession?.user.id
    }

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
        }
        .disabled(isLoading)
        .accessibilityLabel(isSaved ? "Saved" : "Save")
        .task { await refresh() }
    }

    private func refresh() async {
        guard let currentUserID else { return }
        isSaved =
            (try? await Engagement.exists(
                table: "saves",
                filters: ["user_id": currentUserID, "project_id": projectID]
            )) ?? false
    }

    private func toggle() async {
        guard let currentUserID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if isSaved {
                try await Engagement.remove(
                    table: "saves",
                    filters: ["user_id": currentUserID, "project_id": projectID]
                )
                isSaved = false
            } else {
                try await Engagement.insert(
                    table: "saves",
                    values: ["user_id": currentUserID, "project_id": projectID]
                )
                isSaved = true
            }
        } catch {
            AppLogger.network.error("Save toggle failed: \(error.localizedDescription)")
        }
    }
}
