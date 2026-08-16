import SwiftUI
import Supabase

struct ChangePasswordView: View {
    /// Closes the whole Settings sheet after a successful change, rather
    /// than just popping back to the Settings list — there's nothing left
    /// to do here once the password's updated.
    var onSuccess: (() -> Void)?

    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didSucceed = false

    private var isValid: Bool {
        newPassword.count >= 6 && newPassword == confirmPassword
    }

    var body: some View {
        Form {
            Section {
                SecureField("New password", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirmPassword)
                    .textContentType(.newPassword)
            } footer: {
                if !newPassword.isEmpty && newPassword.count < 6 {
                    Text("Password must be at least 6 characters.")
                } else if !confirmPassword.isEmpty && newPassword != confirmPassword {
                    Text("Passwords don't match.")
                } else {
                    Text("You'll stay signed in on this device after changing your password.")
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            if didSucceed {
                Label("Password updated", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .navigationTitle("Change password")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        didSucceed = false
        defer { isSaving = false }
        do {
            try await SupabaseManager.shared.client.auth.update(user: UserAttributes(password: newPassword))
            didSucceed = true
            newPassword = ""
            confirmPassword = ""
            try? await Task.sleep(for: .milliseconds(700))
            onSuccess?()
        } catch {
            AppLogger.auth.error("Password update failed: \(error.localizedDescription)")
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}
