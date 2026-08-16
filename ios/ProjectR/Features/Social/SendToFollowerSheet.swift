import SwiftUI

/// Reached only via "Send in ProjectR" inside the real system share sheet
/// (see `ActivityShareSheet`) — this is no longer the first thing that
/// opens when someone taps Share, just the one path that needs an
/// in-app picker (who to send to) rather than handing off to iOS. Same
/// mini-window pattern as `CommentsSection`: swipe down to dismiss, no
/// close button.
struct SendToFollowerSheet: View {
    /// The plain-text message to send — callers build this themselves
    /// (a project link, a Forge commit summary, whatever) so this sheet
    /// stays generic over what's being shared.
    let messageBody: String
    /// Set when sharing a Forge object, so the recipient's bubble renders
    /// as a rich card instead of plain linkified text.
    var metadata: ForgeShareMetadata?

    @State private var following: [Profile] = []
    @State private var isLoading = false
    @State private var sentTo: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && following.isEmpty {
                    ProgressView()
                } else if following.isEmpty {
                    ContentUnavailableView(
                        "Nobody to send to yet", systemImage: "person.2",
                        description: Text("Follow some builders and they'll show up here."))
                } else {
                    List {
                        Section("Send to") {
                            ForEach(following) { profile in
                                sendRow(profile)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Send in ProjectR")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadFollowing() }
        }
    }

    private func sendRow(_ profile: Profile) -> some View {
        Button {
            Task { await send(to: profile) }
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: profile.avatarURL.flatMap(URL.init)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.accentColor.opacity(0.2)).overlay(
                        Text(profile.displayName.prefix(1).uppercased())
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    )
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName).font(.subheadline.weight(.semibold))
                    Text("@\(profile.username)").font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                if sentTo.contains(profile.id) {
                    Label("Sent", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .labelStyle(.iconOnly)
                }
            }
            .foregroundStyle(.primary)
        }
        .disabled(sentTo.contains(profile.id))
    }

    private func loadFollowing() async {
        guard let myID = SupabaseManager.shared.client.auth.currentSession?.user.id else { return }
        isLoading = true
        defer { isLoading = false }
        // Project-level follows have no `followee_profile_id`, so the
        // embed comes back null for those rows — decoding it as Optional
        // and dropping the nils is simpler than fighting PostgREST's
        // `is`-operator typing for a literal null filter value.
        let rows: [FollowRow] =
            (try? await SupabaseManager.shared.client
                .from("follows")
                .select("followee:profiles!follows_followee_profile_id_fkey(*)")
                .eq("follower_id", value: myID)
                .execute()
                .value) ?? []
        following = rows.compactMap(\.followee)
    }

    private func send(to profile: Profile) async {
        guard let myID = SupabaseManager.shared.client.auth.currentSession?.user.id else { return }
        let (userOne, userTwo) =
            myID.uuidString < profile.id.uuidString ? (myID, profile.id) : (profile.id, myID)

        do {
            let conversation: Conversation =
                try await SupabaseManager.shared.client
                .from("conversations")
                .upsert(
                    ["user_one_id": userOne.uuidString, "user_two_id": userTwo.uuidString],
                    onConflict: "user_one_id,user_two_id"
                )
                .select(
                    """
                    *, \
                    user_one:profiles!conversations_user_one_id_fkey(username,display_name,avatar_url), \
                    user_two:profiles!conversations_user_two_id_fkey(username,display_name,avatar_url)
                    """
                )
                .single()
                .execute()
                .value

            try await SupabaseManager.shared.client
                .from("messages")
                .insert(
                    NewMessage(conversationID: conversation.id, senderID: myID, body: messageBody, metadata: metadata)
                )
                .execute()

            withAnimation { _ = sentTo.insert(profile.id) }
        } catch {
            AppLogger.network.error("Share-to-follower failed: \(error.localizedDescription)")
        }
    }
}

private struct FollowRow: Decodable {
    let followee: Profile?
}

private struct NewMessage: Encodable {
    let conversationID: UUID
    let senderID: UUID
    let body: String
    let metadata: ForgeShareMetadata?

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case senderID = "sender_id"
        case body, metadata
    }
}
