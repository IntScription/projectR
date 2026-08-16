import Supabase
import SwiftUI

struct ChatThreadView: View {
    let conversationID: UUID
    let otherUserID: UUID
    let otherSummary: UserSummary

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var theme: ChatTheme = .default
    @State private var isPresentingThemePicker = false
    @State private var messagePendingDeleteID: UUID?
    @State private var didDeleteMessage = false

    private var currentUserID: UUID? {
        SupabaseManager.shared.client.auth.currentSession?.user.id
    }

    var body: some View {
        let palette = theme.palette
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { message in
                            messageRow(message, palette: palette).id(message.id)
                        }
                    }
                    .padding(16)
                }
                .background(palette.background)
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red).padding(.horizontal)
            }
            composer(palette: palette)
        }
        .floatingTabBarClearance()
        .navigationTitle(otherSummary.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingThemePicker = true
                } label: {
                    Image(systemName: "paintpalette")
                }
                .accessibilityLabel("Change chat theme")
            }
        }
        .sheet(isPresented: $isPresentingThemePicker) {
            ChatThemePickerSheet(conversationID: conversationID, currentTheme: $theme)
        }
        .confirmationDialog(
            "Unsend this message?",
            isPresented: Binding(
                get: { messagePendingDeleteID != nil }, set: { if !$0 { messagePendingDeleteID = nil } }),
            titleVisibility: .visible
        ) {
            Button("Unsend", role: .destructive) { Task { await deleteMessage() } }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: didDeleteMessage) { _, newValue in newValue }
        // This NavigationStack (chat's own) has no `ProjectDetailView`
        // ancestor the way Home/Discover's do, so `ForgeDestination`
        // needs its own registration here too for `ForgeShareCard` taps
        // to navigate — same reasoning as every other tab needing its own
        // `.navigationDestination(for: UUID.self)` for project pushes.
        .navigationDestination(for: ForgeDestination.self) { destination in
            switch destination {
            case .files(let githubURL, let path, let projectID, let branch):
                ForgeFileBrowserView(githubURL: githubURL, path: path, projectID: projectID, branch: branch)
            case .file(let githubURL, let path, let projectID, let branch):
                ForgeCodeViewerView(githubURL: githubURL, path: path, projectID: projectID, branch: branch)
            case .commits(let githubURL, let branch, let projectID):
                ForgeCommitListView(githubURL: githubURL, branch: branch, projectID: projectID)
            case .commitDetail(let githubURL, let sha, let projectID):
                ForgeCommitDetailView(githubURL: githubURL, sha: sha, projectID: projectID)
            case .branches(let githubURL, let projectID):
                ForgeBranchListView(githubURL: githubURL, projectID: projectID)
            case .insights(let githubURL, let projectID):
                ForgeRepoInsightsView(githubURL: githubURL, projectID: projectID)
            }
        }
        .navigationDestination(for: ForgeLocalFileRoute.self) { route in
            ForgeLocalFileEditorView(githubURL: route.githubURL, path: route.path, projectID: route.projectID)
        }
        .task { await load() }
        .task { await subscribeToNewMessages() }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage, palette: ChatTheme.Palette) -> some View {
        let isMine = message.senderID == currentUserID
        HStack {
            if isMine { Spacer(minLength: 40) }
            if let metadata = message.metadata {
                ForgeShareCard(metadata: metadata)
            } else {
                LinkifiedText(text: message.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        isMine ? palette.myBubble : palette.theirBubble,
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                    .foregroundStyle(isMine ? palette.myText : palette.theirText)
                    .contextMenu {
                        if isMine {
                            Button(role: .destructive) {
                                messagePendingDeleteID = message.id
                            } label: {
                                Label("Unsend", systemImage: "trash")
                            }
                        }
                    }
            }
            if !isMine { Spacer(minLength: 40) }
        }
    }

    private func composer(palette: ChatTheme.Palette) -> some View {
        HStack(spacing: 10) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title2)
            }
            .tint(palette.accent)
            .accessibilityLabel("Send message")
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding(12)
        .background(.bar)
    }

    private func load() async {
        do {
            async let messagesTask: [ChatMessage] =
                SupabaseManager.shared.client
                .from("messages")
                .select()
                .eq("conversation_id", value: conversationID)
                .order("created_at", ascending: true)
                .execute()
                .value
            async let themeTask: ConversationTheme =
                SupabaseManager.shared.client
                .from("conversations")
                .select("theme")
                .eq("id", value: conversationID)
                .single()
                .execute()
                .value

            messages = try await messagesTask
            if let fetchedTheme = try? await themeTask,
                let resolved = ChatTheme(rawValue: fetchedTheme.theme)
            {
                theme = resolved
            }
            await markRead()
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func markRead() async {
        guard let currentUserID else { return }
        try? await SupabaseManager.shared.client
            .from("messages")
            .update(["read_at": ISO8601DateFormatter().string(from: Date())])
            .eq("conversation_id", value: conversationID)
            .neq("sender_id", value: currentUserID)
            .is("read_at", value: nil)
            .execute()
    }

    private func send() async {
        guard let currentUserID else { return }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        draft = ""
        do {
            try await SupabaseManager.shared.client
                .from("messages")
                .insert(
                    NewMessage(conversationID: conversationID, senderID: currentUserID, body: body)
                )
                .execute()
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func deleteMessage() async {
        guard let messageID = messagePendingDeleteID else { return }
        messagePendingDeleteID = nil
        do {
            try await SupabaseManager.shared.client
                .from("messages")
                .delete()
                .eq("id", value: messageID)
                .execute()
            messages.removeAll { $0.id == messageID }
            didDeleteMessage = true
            AnalyticsService.track("message_deleted")
        } catch {
            CrashReporter.capture(error, context: "delete_message")
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func subscribeToNewMessages() async {
        let channel = SupabaseManager.shared.client.channel("conversation:\(conversationID.uuidString)")
        let changes = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "messages",
            filter: .eq("conversation_id", value: conversationID.uuidString)
        )
        await channel.subscribe()

        for await change in changes {
            guard let inserted = try? change.decodeRecord(as: ChatMessage.self, decoder: Self.realtimeDecoder)
            else { continue }
            if !messages.contains(where: { $0.id == inserted.id }) {
                messages.append(inserted)
                if inserted.senderID != currentUserID {
                    await markRead()
                }
            }
        }
    }

    /// `postgresChange`'s decode step doesn't share the PostgREST client's
    /// configured decoder, so Postgres's fractional-seconds timestamp
    /// format needs handling here too — same two-pass ISO8601 fallback
    /// supabase-swift uses internally (that helper is package-private, not
    /// something this module can call directly).
    private static var realtimeDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let withFractional = Date.ISO8601FormatStyle()
                .year().month().day()
                .dateTimeSeparator(.standard)
                .time(includingFractionalSeconds: true)
            let withoutFractional = Date.ISO8601FormatStyle()
                .year().month().day()
                .dateTimeSeparator(.standard)
                .time(includingFractionalSeconds: false)
            if let date = try? Date(string, strategy: withFractional) {
                return date
            }
            if let date = try? Date(string, strategy: withoutFractional) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid date format: \(string)")
        }
        return decoder
    }
}

private struct ConversationTheme: Decodable {
    let theme: String
}

private struct NewMessage: Encodable {
    let conversationID: UUID
    let senderID: UUID
    let body: String

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case senderID = "sender_id"
        case body
    }
}
