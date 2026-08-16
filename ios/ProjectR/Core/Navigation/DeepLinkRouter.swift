import Foundation
import Observation

/// Holds a deep link until the app is in a state that can act on it
/// (signed in, past onboarding). `ProjectRApp` sets `pendingDestination` in
/// `.onOpenURL`; `RootTabView` consumes and clears it once the tab
/// structure exists to navigate within.
@MainActor
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    var pendingDestination: DeepLink?

    private init() {}

    func handle(url: URL) {
        guard let destination = DeepLink(url: url) else { return }
        pendingDestination = destination
    }
}
