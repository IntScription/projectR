import SwiftUI

struct SettingsView: View {
    @Binding var profile: Profile
    let auth: AuthViewModel

    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("requireFaceID") private var requireFaceID = false
    @Environment(\.dismiss) private var dismiss

    @State private var isPresentingSignOutConfirm = false
    @State private var currentLevel = 0

    /// Powerlevel10k only shows up once actually unlocked (level 10,000 —
    /// the max achievement's reward) — everyone else just sees the three
    /// original options, same as before this existed.
    private var availableThemes: [AppTheme] {
        AppTheme.allCases.filter { $0 != .powerlevel10k || currentLevel >= Achievement.maxLevel }
    }

    var body: some View {
        List {
            Section {
                Picker("Theme", selection: $appThemeRaw) {
                    ForEach(availableThemes) { theme in
                        Text(theme.label).tag(theme.rawValue)
                    }
                }
            } header: {
                Text("Appearance")
            } footer: {
                if currentLevel < Achievement.maxLevel {
                    Text("Reach level \(Achievement.maxLevel) to unlock the Powerlevel10k theme.")
                }
            }

            Section {
                Toggle("Require Face ID", isOn: $requireFaceID)
            } header: {
                Text("Security")
            } footer: {
                Text("Locks ProjectR behind Face ID (or your passcode) whenever it returns from the background.")
            }

            Section("Account") {
                NavigationLink("Change username") {
                    ChangeUsernameView(profile: $profile)
                }
                NavigationLink("Change password") {
                    ChangePasswordView(onSuccess: dismiss.callAsFunction)
                }
                Button("Sign out", role: .destructive) {
                    isPresentingSignOutConfirm = true
                }
            }

            GitHubSettingsSection()

            Section("Levels") {
                NavigationLink("Achievements") {
                    AchievementsListView(profileID: profile.id)
                }
            }

            Section {
                NavigationLink("Portfolio PDF") {
                    PortfolioBuilderView(profile: profile)
                }
            } header: {
                Text("Portfolio")
            } footer: {
                Text("Generate a real PDF from your projects — bios, tech stack, and real GitHub stats, ready to share or attach to an application.")
            }

            if profile.isAdmin {
                Section("Moderation") {
                    NavigationLink("Reports") {
                        ModerationQueueView()
                    }
                }
            }

            Section {
                NavigationLink("About") { AboutView() }
            }

            Section {
                NavigationLink("Delete Account") {
                    DeleteAccountView(profile: profile, auth: auth)
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .confirmationDialog(
            "Sign out of ProjectR?", isPresented: $isPresentingSignOutConfirm, titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) { Task { await auth.signOut() } }
        }
        .task {
            currentLevel = await ProfileLevelService.fetch(profileID: profile.id)?.level ?? 0
        }
    }
}
