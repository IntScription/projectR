import UIKit

/// SwiftUI's `App` protocol has no hook for
/// `didRegisterForRemoteNotificationsWithDeviceToken` — that's still a
/// UIApplicationDelegate callback, hence this small bridge via
/// `@UIApplicationDelegateAdaptor` in `ProjectRApp`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        Task {
            await PushRegistrar.registerToken(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Expected to fail without a paid Apple Developer account's APNs
        // entitlement — see PushRegistrar.
        print("Remote notification registration failed: \(error)")
    }
}
