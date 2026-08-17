import SwiftUI

struct RootView: View {
    @State private var auth = AuthViewModel()
    @State private var profile: Profile?
    @State private var isCheckingProfile = false
    @State private var justOnboarded = false
    /// Separate from `justOnboarded` — that one only gates *which screen*
    /// shows next (SuggestedFollowsView), and flips back to false once
    /// that's done. This one needs to survive through that screen and
    /// still be true the one time `RootTabView` actually gets created, so
    /// it (and only it) can start on the Add tab instead of Home — a
    /// brand-new account has nothing to browse yet, so "make something"
    /// is a better first landing than an empty Home feed. A returning
    /// session's `RootTabView` creation never sets this, so it keeps the
    /// normal Home default.
    @State private var justCompletedOnboarding = false

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
                RootTabView(auth: auth, profile: profileBinding, startOnAddTab: justCompletedOnboarding)
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
                    justCompletedOnboarding = true
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
        // Deliberately *not* resetting `profile` to nil here on sign-out.
        // `RootTabView` is built from a force-unwrapping `Binding($profile)`
        // (`if let profileBinding = Binding($profile)`) — nil-ing the
        // source `@State` out from under that binding while `RootTabView`
        // is still mid-teardown (the `auth.session == nil` branch swap
        // happens in the same update pass this task's state change
        // triggers) is exactly what crashes: `BindingOperations.
        // ForceUnwrapping.get` explodes reading a now-nil value. Leaving
        // the stale `Profile` in place instead is harmless — nothing
        // reads it once `WelcomeView` is showing, and the next real
        // sign-in overwrites it correctly below before any new
        // `RootTabView` is created.
        guard let userID = auth.session?.user.id else {
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
