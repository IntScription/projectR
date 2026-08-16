import SwiftUI

struct FollowButton: View {
    enum Target: Hashable {
        case profile(UUID)
        case project(UUID)
    }

    let target: Target

    @State private var isFollowing = false
    @State private var followerCount = 0
    @State private var isLoading = false

    private var currentUserID: UUID? {
        SupabaseManager.shared.client.auth.currentSession?.user.id
    }

    private var targetColumn: String {
        switch target {
        case .profile: "followee_profile_id"
        case .project: "followee_project_id"
        }
    }

    private var targetID: UUID {
        switch target {
        case .profile(let id), .project(let id): id
        }
    }

    /// Following yourself isn't meaningful; following your own project is.
    private var isDisabled: Bool {
        isLoading || (isProfileTarget && currentUserID == targetID)
    }

    private var isProfileTarget: Bool {
        if case .profile = target { return true }
        return false
    }

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isFollowing ? "checkmark" : "plus")
                Text(isFollowing ? "Following" : "Follow")
                if followerCount > 0 {
                    Text("· \(followerCount)").foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.bordered)
        .disabled(isDisabled)
        .task { await refresh() }
    }

    private func refresh() async {
        async let countTask = Engagement.count(table: "follows", filters: [targetColumn: targetID])
        if let currentUserID {
            isFollowing =
                (try? await Engagement.exists(
                    table: "follows",
                    filters: ["follower_id": currentUserID, targetColumn: targetID]
                )) ?? false
        }
        followerCount = (try? await countTask) ?? 0
    }

    private func toggle() async {
        guard let currentUserID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if isFollowing {
                try await Engagement.remove(
                    table: "follows",
                    filters: ["follower_id": currentUserID, targetColumn: targetID]
                )
                isFollowing = false
                followerCount = max(0, followerCount - 1)
            } else {
                try await Engagement.insert(
                    table: "follows",
                    values: ["follower_id": currentUserID, targetColumn: targetID]
                )
                isFollowing = true
                followerCount += 1
            }
        } catch {
            // Best-effort toggle — a failed request just leaves state unchanged
            // (this can now legitimately fail if a block exists between the
            // two profiles, not just on network errors).
            AppLogger.network.error("Follow toggle failed: \(error.localizedDescription)")
        }
    }
}
