import SwiftUI

/// Chip editor for a project's tech stack. GitHub enrichment fills this in
/// automatically from the repo's real language breakdown, but language
/// detection only sees file extensions — it has no way to know a
/// TypeScript+JavaScript repo is actually a React Native app, or that a
/// Python repo is a Django project. This lets someone add whatever
/// framework/tool actually describes what they built, on top of whatever
/// auto-detection already found. Whatever ends up in the list is what
/// counts toward skills — the level formula reads the whole array, not
/// just GitHub-sourced entries.
struct TechStackEditor: View {
    @Binding var techStack: [String]
    @State private var newTech = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !techStack.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(techStack, id: \.self) { tech in
                        chip(tech)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Add a technology (e.g. React Native)", text: $newTech)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($isFieldFocused)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newTech.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func chip(_ tech: String) -> some View {
        HStack(spacing: 6) {
            Text(tech).font(.subheadline.weight(.medium))
            Button {
                techStack.removeAll { $0 == tech }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Remove \(tech)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
        .fixedSize()
    }

    private func add() {
        let trimmed = newTech.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if !techStack.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            techStack.append(trimmed)
        }
        newTech = ""
        isFieldFocused = true
    }
}
