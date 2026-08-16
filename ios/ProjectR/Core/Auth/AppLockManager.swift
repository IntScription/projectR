import LocalAuthentication
import Observation

/// Local device-unlock gate — separate from `AuthViewModel`'s Supabase
/// session. This never touches the network; it just decides whether the
/// already-signed-in UI is visible on *this* device right now, protecting
/// a left-unlocked phone rather than the account itself.
@MainActor
@Observable
final class AppLockManager {
    /// A dedicated gate for Forge, separate from the app-wide lock
    /// (which is opt-in via a Settings toggle and off by default).
    /// Forge can browse, edit, and commit real code through a connected
    /// GitHub account — worth its own always-on gate. Shared as a
    /// singleton rather than owned by one view, since `ForgeRoute`
    /// resolves to `ForgeView` from two separate places (the Forge tab,
    /// and a project's own toolbar hammer button) — one shared instance
    /// means unlocking from either entry point unlocks both, instead of
    /// asking twice in the same session.
    static let forge = AppLockManager(isLocked: true)

    var isLocked: Bool
    private(set) var isAuthenticating = false

    init(isLocked: Bool = false) {
        self.isLocked = isLocked
    }

    /// Called when the app backgrounds while the "Require Face ID" setting
    /// is on, so returning to the foreground shows the lock screen instead
    /// of momentarily flashing the previous screen's content.
    func lock() {
        isLocked = true
    }

    func authenticate(reason: String = "Unlock ProjectR") async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        var policyError: NSError?
        // deviceOwnerAuthentication (not the biometrics-only variant) also
        // falls back to the passcode, matching how every other iOS app
        // with a Face ID lock behaves — Face ID failing shouldn't strand
        // someone out of their own app.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            // No biometrics/passcode enrolled on this device (or simulator)
            // — nothing to gate against, so don't lock the user out.
            isLocked = false
            return
        }

        let success =
            (try? await context.evaluatePolicy(
                .deviceOwnerAuthentication, localizedReason: reason)) ?? false
        if success {
            isLocked = false
        }
    }
}
