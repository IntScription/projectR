import SwiftUI

extension View {
    /// Reserves clearance for `RootTabView`'s floating tab bar. That bar's
    /// own `.safeAreaInset` lives on the `ZStack` wrapping all five tab
    /// `NavigationStack`s, which correctly insets each stack's *root*
    /// content — but a `.safeAreaInset` set outside a `NavigationStack`
    /// isn't reliably inherited by views pushed *inside* it, so any screen
    /// reached via `.navigationDestination` needs this applied directly,
    /// or its last ~80pt of content ends up hidden behind the floating bar
    /// with no way to scroll it into view.
    func floatingTabBarClearance() -> some View {
        safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 78)
        }
    }
}
