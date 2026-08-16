import SwiftUI

struct NotificationsView: View {
    @State private var notifications: [AppNotification] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && notifications.isEmpty {
                ProgressView()
            } else if notifications.isEmpty {
                ContentUnavailableView("No notifications yet", systemImage: "bell")
            } else {
                List(notifications) { notification in
                    row(for: notification)
                }
                .listStyle(.plain)
            }
        }
        .floatingTabBarClearance()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UUID.self) { ProjectDetailView(projectID: $0) }
        .navigationDestination(for: CreatorRoute.self) { CreatorProfileView(userID: $0.userID) }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private func row(for notification: AppNotification) -> some View {
        if let projectID = notification.projectID {
            NavigationLink(value: projectID) {
                NotificationRow(notification: notification)
            }
            .onAppear { Task { await markReadIfNeeded(notification) } }
        } else if notification.type == .note {
            NavigationLink(value: CreatorRoute(userID: notification.actorID)) {
                NotificationRow(notification: notification)
            }
            .onAppear { Task { await markReadIfNeeded(notification) } }
        } else {
            NotificationRow(notification: notification)
                .onAppear { Task { await markReadIfNeeded(notification) } }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            notifications =
                try await SupabaseManager.shared.client
                .from("notifications")
                .select(
                    "*, actor:profiles!notifications_actor_id_fkey(username, display_name, avatar_url)"
                )
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func markReadIfNeeded(_ notification: AppNotification) async {
        guard !notification.isRead else { return }
        guard let index = notifications.firstIndex(where: { $0.id == notification.id }) else {
            return
        }
        notifications[index].isRead = true
        try? await SupabaseManager.shared.client
            .from("notifications")
            .update(["is_read": true])
            .eq("id", value: notification.id)
            .execute()
    }
}
