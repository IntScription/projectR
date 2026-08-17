import Foundation

/// Builds the public web URLs used by `ShareLink` — the same routes the web
/// app serves, read from Config.local.xcconfig's SITE_URL so it points at
/// whatever's running locally without a code change.
enum ShareLinks {
    private static var siteURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "SiteURL") as? String) ?? "https://web-navy-eight-82.vercel.app"
    }

    static func project(slug: String) -> URL {
        URL(string: "\(siteURL)/p/\(slug)") ?? URL(string: "https://web-navy-eight-82.vercel.app")!
    }

    static func profile(username: String) -> URL {
        URL(string: "\(siteURL)/@\(username)") ?? URL(string: "https://web-navy-eight-82.vercel.app")!
    }
}
