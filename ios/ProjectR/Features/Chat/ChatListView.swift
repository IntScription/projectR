import Supabase
import SwiftUI

/// Navigation value for pushing a thread — carries the other participant's
/// summary along so `ChatThreadView` doesn't need a second fetch just to
/// show a name in the nav title.
struct ChatRoute: Hashable {
    let conversationID: UUID
    let otherUserID: UUID
    let otherSummary: UserSummary
}

struct ChatListView: View {
    @State private var conversations: [Conversation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var currentUserID: UUID? {
        SupabaseManager.shared.client.auth.currentSession?.user.id
    }

    var body: some View {
        Group {
            if isLoading && conversations.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if conversations.isEmpty {
                ContentUnavailableView(
                    "No conversations yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Message a creator from their profile to start one.")
                )
            } else if let currentUserID {
                List(conversations) { conversation in
                    let other = conversation.otherParticipant(currentUserID: currentUserID)
                    NavigationLink(
                        value: ChatRoute(
                            conversationID: conversation.id, otherUserID: other.id,
                            otherSummary: other.summary)
                    ) {
                        ConversationRow(summary: other.summary, lastMessageAt: conversation.lastMessageAt)
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }
        }
        .floatingTabBarClearance()
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: ChatRoute.self) { route in
            ChatThreadView(
                conversationID: route.conversationID, otherUserID: route.otherUserID,
                otherSummary: route.otherSummary)
        }
        .task { await load() }
        .task { await subscribeToChanges() }
    }

    /// Reloads on any new message (bumps ordering) or any new conversation
    /// (someone just started one with you) rather than trying to filter
    /// "conversations I'm in" through `postgres_changes`' filter DSL — the
    /// reload itself is RLS-scoped, so this only ever costs an extra cheap
    /// query, never shows someone else's conversation.
    private func subscribeToChanges() async {
        let channel = SupabaseManager.shared.client.channel("app:chat-list")
        let newMessages = channel.postgresChange(InsertAction.self, schema: "public", table: "messages")
        let newConversations = channel.postgresChange(
            InsertAction.self, schema: "public", table: "conversations")
        await channel.subscribe()

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in newMessages { await load() }
            }
            group.addTask {
                for await _ in newConversations { await load() }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // RLS already scopes this to conversations the caller
            // participates in — no need to filter by user id again here.
            conversations =
                try await SupabaseManager.shared.client
                .from("conversations")
                .select(
                    """
                    *, \
                    user_one:profiles!conversations_user_one_id_fkey(username,display_name,avatar_url), \
                    user_two:profiles!conversations_user_two_id_fkey(username,display_name,avatar_url)
                    """
                )
                .order("last_message_at", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}
