import Foundation

/// Parses both the custom scheme (works today, no external dependency —
/// `projectr://project/slug`, `projectr://profile/username`) and Universal
/// Links matching the web app's real routes (`https://projectr.app/p/slug`,
/// `https://projectr.app/@username`) — the latter only actually routes to
/// the app once the AASA file is live on the real domain with the real
/// Team ID; see README.
enum DeepLink: Hashable {
    case profile(username: String)
    case project(slug: String)

    init?(url: URL) {
        if url.scheme == "projectr" {
            guard let identifier = url.pathComponents.filter({ $0 != "/" }).first else {
                return nil
            }
            switch url.host {
            case "profile": self = .profile(username: identifier)
            case "project": self = .project(slug: identifier)
            default: return nil
            }
        } else {
            let components = url.pathComponents.filter { $0 != "/" }
            guard let first = components.first else { return nil }
            if first.hasPrefix("@") {
                self = .profile(username: String(first.dropFirst()))
            } else if first == "p", components.count >= 2 {
                self = .project(slug: components[1])
            } else {
                return nil
            }
        }
    }
}
