import SwiftUI

/// Instagram-style comments drawer — presented as a sheet (see
/// `CommentButton`) rather than living inline on the page, with the
/// comment list filling the sheet and the input bar pinned to the bottom.
struct CommentsSection: View {
    enum Target: Hashable {
        case project(UUID)
        case update(UUID)
    }

    let target: Target
    var onCountChanged: ((Int) -> Void)?

    @State private var comments: [Comment] = []
    @State private var newCommentText = ""
    @State private var isLoading = false
    @State private var isPosting = false
    @State private var commentPendingDeleteID: UUID?
    @State private var didDeleteComment = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

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

    var body: some View {
        NavigationStack {
            Group {
                if comments.isEmpty && !isLoading {
                    ContentUnavailableView("No comments yet", systemImage: "bubble.left")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(comments) { comment in
                                commentRow(comment)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 14)
                    }
                    inputBar
                }
            }
            .confirmationDialog(
                "Delete this comment?",
                isPresented: Binding(
                    get: { commentPendingDeleteID != nil }, set: { if !$0 { commentPendingDeleteID = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { Task { await deleteComment() } }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: didDeleteComment) { _, newValue in newValue }
            .task { await load() }
        }
    }

    private func commentRow(_ comment: Comment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: comment.author.avatarURL.flatMap(URL.init)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(.secondary.opacity(0.2))
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                (Text(comment.author.displayName).fontWeight(.semibold) + Text(" " + comment.body))
                    .font(.subheadline)
                Text(comment.createdAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if comment.userID == currentUserID {
                Spacer()
                Button {
                    commentPendingDeleteID = comment.id
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete comment")
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Add a comment…", text: $newCommentText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                .lineLimit(1...4)
                .focused($isInputFocused)

            Button {
                Task { await post() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
            }
            .disabled(
                newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
            .accessibilityLabel("Post comment")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            comments =
                try await SupabaseManager.shared.client
                .from("comments")
                .select(
                    "*, author:profiles!comments_user_id_fkey(username, display_name, avatar_url)"
                )
                .eq(targetColumn, value: targetID)
                .order("created_at", ascending: true)
                .execute()
                .value
            onCountChanged?(comments.count)
        } catch {
            comments = []
        }
    }

    private func post() async {
        guard let currentUserID = SupabaseManager.shared.client.auth.currentSession?.user.id
        else { return }
        let trimmed = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isPosting = true
        defer { isPosting = false }

        let newComment: NewComment
        switch target {
        case .project(let id):
            newComment = NewComment(userID: currentUserID, projectID: id, updateID: nil, body: trimmed)
        case .update(let id):
            newComment = NewComment(userID: currentUserID, projectID: nil, updateID: id, body: trimmed)
        }

        do {
            let created: Comment =
                try await SupabaseManager.shared.client
                .from("comments")
                .insert(newComment)
                .select(
                    "*, author:profiles!comments_user_id_fkey(username, display_name, avatar_url)"
                )
                .single()
                .execute()
                .value
            comments.append(created)
            newCommentText = ""
            errorMessage = nil
            onCountChanged?(comments.count)
        } catch {
            // Leave the draft in place so the user can retry.
            CrashReporter.capture(error, context: "post_comment")
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func deleteComment() async {
        guard let commentID = commentPendingDeleteID else { return }
        commentPendingDeleteID = nil
        do {
            try await SupabaseManager.shared.client
                .from("comments")
                .delete()
                .eq("id", value: commentID)
                .execute()
            comments.removeAll { $0.id == commentID }
            onCountChanged?(comments.count)
            didDeleteComment = true
        } catch {
            // The row staying visible here is correct either way: if this
            // genuinely wasn't the comment's own author, RLS silently
            // no-ops rather than throwing, so reaching this `catch` at all
            // means a real network/transient failure — worth surfacing
            // now that it's not just a swallowed comment.
            CrashReporter.capture(error, context: "delete_comment")
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}

private struct NewComment: Encodable {
    let userID: UUID
    let projectID: UUID?
    let updateID: UUID?
    let body: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case projectID = "project_id"
        case updateID = "update_id"
        case body
    }
}
