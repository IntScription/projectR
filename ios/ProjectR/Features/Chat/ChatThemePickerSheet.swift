import SwiftUI

struct ChatThemePickerSheet: View {
    let conversationID: UUID
    @Binding var currentTheme: ChatTheme

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ChatTheme.allCases) { theme in
                        swatch(for: theme)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Chat theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func swatch(for theme: ChatTheme) -> some View {
        let palette = theme.palette
        return Button {
            Task { await select(theme) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(palette.myBubble).frame(width: 16, height: 16)
                    Circle().fill(palette.theirBubble).frame(width: 16, height: 16)
                    Circle().fill(palette.accent).frame(width: 16, height: 16)
                    Spacer()
                    if theme == currentTheme {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(palette.accent)
                    }
                }
                Text(theme.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.theirText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(theme == currentTheme ? palette.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    private func select(_ theme: ChatTheme) async {
        isSaving = true
        defer { isSaving = false }
        let previous = currentTheme
        currentTheme = theme
        do {
            try await SupabaseManager.shared.client
                .from("conversations")
                .update(["theme": theme.rawValue])
                .eq("id", value: conversationID)
                .execute()
        } catch {
            currentTheme = previous
        }
    }
}
