import GoogleSignIn
import Supabase
import SwiftUI

@main
struct ProjectRApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue

    init() {
        CrashReporter.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(AppTheme(rawValue: appThemeRaw)?.colorScheme)
                // `nil` for every theme except Powerlevel10k — `.tint(nil)`
                // is a real, valid call (not "no override"), it just
                // resolves to the same asset-catalog `AccentColor` every
                // other theme already uses, so this is safe to apply
                // unconditionally rather than branching.
                .tint(AppTheme(rawValue: appThemeRaw)?.accentColor)
                .onOpenURL { url in
                    if url.scheme == "projectr" && url.host == "auth-callback" {
                        // GitHub identity linking is a browser round trip
                        // (no native SDK) — this finishes the PKCE exchange
                        // GitHubService.connect() started.
                        Task { try? await SupabaseManager.shared.client.auth.session(from: url) }
                    } else if !GIDSignIn.sharedInstance.handle(url) {
                        DeepLinkRouter.shared.handle(url: url)
                    }
                }
        }
    }
}
