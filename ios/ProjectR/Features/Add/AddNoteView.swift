import SwiftUI

struct AddNoteView: View {
    let authorID: UUID
    var onPosted: ((Note) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var body_ = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    private let limit = 280

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("What's on your mind?", text: $body_, axis: .vertical)
                    .lineLimit(6...12)
                    .focused($isFocused)
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack {
                    Spacer()
                    Text("\(body_.count)/\(limit)")
                        .font(.caption)
                        .foregroundStyle(body_.count > limit ? .red : .secondary)
                }

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Post") { Task { await post() } }
                            .disabled(
                                body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || body_.count > limit)
                    }
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(200))
                isFocused = true
            }
        }
        .presentationDetents([.medium])
    }

    private func post() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let created: Note =
                try await SupabaseManager.shared.client
                .from("notes")
                .insert(NewNote(authorID: authorID, body: body_.trimmingCharacters(in: .whitespacesAndNewlines)))
                .select()
                .single()
                .execute()
                .value
            onPosted?(created)
            dismiss()
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}

private struct NewNote: Encodable {
    let authorID: UUID
    let body: String

    enum CodingKeys: String, CodingKey {
        case authorID = "author_id"
        case body
    }
}
