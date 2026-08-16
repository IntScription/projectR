import SwiftUI

struct RootView: View {
    @State private var auth = AuthViewModel()
    @State private var profile: Profile?
    @State private var isCheckingProfile = false
    @State private var justOnboarded = false

    @AppStorage("requireFaceID") private var requireFaceID = false
    @State private var appLock = AppLockManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if auth.session == nil {
                NavigationStack {
                    WelcomeView(auth: auth)
                }
            } else if isCheckingProfile {
                ProgressView()
            } else if justOnboarded {
                SuggestedFollowsView { justOnboarded = false }
            } else if let profileBinding = Binding($profile) {
                RootTabView(auth: auth, profile: profileBinding)
                    .fullScreenCover(isPresented: Binding(
                        get: { requireFaceID && appLock.isLocked },
                        set: { appLock.isLocked = $0 }
                    )) {
                        AppLockView(appLock: appLock)
                    }
            } else if let userID = auth.session?.user.id {
                OnboardingView(userID: userID) { createdProfile in
                    profile = createdProfile
                    justOnboarded = true
                }
            }
        }
        .task(id: auth.session?.user.id) {
            await loadProfile()
        }
        .task(id: requireFaceID) {
            // Start locked immediately if the setting is on when the
            // signed-in UI first appears — not just on the next backgrounding.
            if requireFaceID { appLock.isLocked = true }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard requireFaceID, auth.session != nil else { return }
            if newPhase == .background {
                appLock.lock()
            }
        }
    }

    private func loadProfile() async {
        guard let userID = auth.session?.user.id else {
            profile = nil
            return
        }
        isCheckingProfile = true
        defer { isCheckingProfile = false }
        profile =
            try? await SupabaseManager.shared.client
            .from("profiles")
            .select()
            .eq("id", value: userID)
            .single()
            .execute()
            .value
    }
}
