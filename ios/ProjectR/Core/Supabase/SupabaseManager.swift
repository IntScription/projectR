import Foundation
import Supabase

enum SupabaseBucket {
    static let avatars = "avatars"
    static let projectMedia = "project-media"
}

final class SupabaseManager: Sendable {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
            let url = URL(string: urlString),
            !anonKey.isEmpty
        else {
            fatalError(
                "Missing Supabase config. Copy ios/Config.local.xcconfig.example to " +
                "ios/Config.local.xcconfig, fill in the values from `supabase start`, " +
                "then re-run `xcodegen generate`."
            )
        }

        client = SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }
}
