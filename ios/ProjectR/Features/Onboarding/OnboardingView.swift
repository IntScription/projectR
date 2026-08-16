import SwiftUI

struct OnboardingView: View {
    let userID: UUID
    var onComplete: (Profile) -> Void

    @State private var username = ""
    @State private var displayName = ""
    @State private var bio = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claim your identity")
                        .font(.title2.bold())
                    Text("Separate from how you signed in — this is what people see on ProjectR.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                labeledField("Username") {
                    HStack {
                        Text("@").foregroundStyle(.secondary)
                        TextField("kartik", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .textFieldStyle(.roundedBorder)
                }

                labeledField("Display name") {
                    TextField("Kartik Sanil", text: $displayName)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Bio") {
                    TextField("What are you building?", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                }

                Text("Your skills aren't typed in — ProjectR works them out automatically from the projects you build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }

                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Continue").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || isSaving)
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func labeledField(
        _ title: String,
        caption: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            content()
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var isValid: Bool {
        Validation.isValidUsername(username)
            && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let newProfile = Profile(
            id: userID,
            username: username.trimmingCharacters(in: .whitespaces),
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            avatarURL: nil,
            bio: bio.isEmpty ? nil : bio,
            skills: [],
            links: []
        )

        do {
            let saved: Profile =
                try await SupabaseManager.shared.client
                .from("profiles")
                .insert(newProfile)
                .select()
                .single()
                .execute()
                .value
            onComplete(saved)
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}
