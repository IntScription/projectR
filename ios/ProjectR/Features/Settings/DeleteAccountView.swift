import SwiftUI

struct DeleteAccountView: View {
    let profile: Profile
    let auth: AuthViewModel

    @State private var confirmationText = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text(
                    "This permanently deletes your account, profile, projects, updates, and everything else attached to it. This can't be undone."
                )
                .foregroundStyle(.secondary)
            }

            Section("Type your username to confirm: \(profile.username)") {
                TextField("Username", text: $confirmationText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            Section {
                Button(role: .destructive) {
                    Task { await deleteAccount() }
                } label: {
                    if isDeleting {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Delete Account").frame(maxWidth: .infinity)
                    }
                }
                .disabled(confirmationText != profile.username || isDeleting)
            }
        }
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func deleteAccount() async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            try await SupabaseManager.shared.client.functions.invoke("delete-account")
            await auth.signOut()
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}
