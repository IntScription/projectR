import Supabase
import UIKit
import UserNotifications

/// Real client-side push plumbing — permission prompt, device token
/// capture, and storing the token in `device_tokens` all genuinely work.
/// What's missing is a sender: actually delivering an APNs push needs an
/// Apple Push Notification key, which needs a paid Apple Developer Program
/// membership (the same blocker already noted for Sign in with Apple in
/// the README) plus a server-side function to call APNs when a
/// `notifications` row is inserted. That's future work, not stubbed here.
enum PushRegistrar {
    @MainActor
    static func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    static func registerToken(_ token: String) async {
        guard let userID = SupabaseManager.shared.client.auth.currentSession?.user.id else { return }
        try? await SupabaseManager.shared.client
            .from("device_tokens")
            .upsert(
                ["user_id": userID.uuidString, "token": token, "platform": "ios"],
                onConflict: "user_id,token"
            )
            .execute()
    }
}
