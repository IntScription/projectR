import SwiftUI

struct ChangeUsernameView: View {
    @Binding var profile: Profile

    @State private var newUsername = ""
    @State private var availability: Availability = .idle
    @State private var isSaving = false
    @State private var errorMessage: String?

    private enum Availability: Equatable {
        case idle, checking, available, taken, invalid
    }

    var body: some View {
        Form {
            Section {
                TextField("Username", text: $newUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                availabilityRow
            } footer: {
                Text("3-30 characters: letters, numbers, and underscores.")
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle("Change username")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(availability != .available)
                }
            }
        }
        .onAppear { newUsername = profile.username }
        .task(id: newUsername) { await checkAvailability() }
    }

    @ViewBuilder
    private var availabilityRow: some View {
        switch availability {
        case .idle: EmptyView()
        case .checking:
            Label("Checking…", systemImage: "ellipsis.circle")
                .foregroundStyle(.secondary)
        case .available:
            Label("Available", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .taken:
            Label("Already taken", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .invalid:
            Label("3-30 letters, numbers, or underscores", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
        }
    }

    private func checkAvailability() async {
        let trimmed = newUsername.trimmingCharacters(in: .whitespaces)

        if trimmed.lowercased() == profile.username.lowercased() {
            availability = .idle
            return
        }
        guard Validation.isValidUsername(trimmed) else {
            availability = .invalid
            return
        }

        availability = .checking
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }

        let taken =
            (try? await Engagement.exists(table: "profiles", filters: ["username": trimmed]))
            ?? true
        availability = taken ? .taken : .available
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let updated: Profile =
                try await SupabaseManager.shared.client
                .from("profiles")
                .update(["username": newUsername.trimmingCharacters(in: .whitespaces)])
                .eq("id", value: profile.id)
                .select()
                .single()
                .execute()
                .value
            profile = updated
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}
