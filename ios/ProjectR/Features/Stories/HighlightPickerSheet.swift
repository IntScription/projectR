import SwiftUI

/// Reused by both the composer ("save this new story straight into a
/// highlight") and the viewer's 3-dot menu ("add this existing story to a
/// highlight") — this sheet only picks *which* highlight; the caller
/// decides what to do with that choice, since the two call sites need to
/// do slightly different things with it (defer vs. insert immediately).
struct HighlightPickerSheet: View {
    let ownerID: UUID
    var onPick: (StoryHighlight) -> Void

    @State private var highlights: [StoryHighlight] = []
    @State private var isLoading = false
    @State private var newTitle = ""
    @State private var isCreating = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New highlight name", text: $newTitle)
                        Button {
                            Task { await createAndPick() }
                        } label: {
                            if isCreating {
                                ProgressView()
                            } else {
                                Text("Create")
                            }
                        }
                        .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                    }
                }
                if isLoading && highlights.isEmpty {
                    ProgressView()
                } else if !highlights.isEmpty {
                    Section("Your highlights") {
                        ForEach(highlights) { highlight in
                            Button {
                                onPick(highlight)
                                dismiss()
                            } label: {
                                Text(highlight.title)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Add to Highlights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        highlights =
            (try? await SupabaseManager.shared.client
                .from("story_highlights")
                .select()
                .eq("owner_id", value: ownerID)
                .order("created_at", ascending: false)
                .execute()
                .value) ?? []
    }

    private func createAndPick() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            let created: StoryHighlight =
                try await SupabaseManager.shared.client
                .from("story_highlights")
                .insert(["owner_id": ownerID.uuidString, "title": title])
                .select()
                .single()
                .execute()
                .value
            onPick(created)
            dismiss()
        } catch {
            AppLogger.stories.error("Failed to create highlight: \(error.localizedDescription)")
        }
    }
}
