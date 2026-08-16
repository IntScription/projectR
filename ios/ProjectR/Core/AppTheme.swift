import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    /// The reward for the max achievement (level 10,000) — see
    /// `Achievement.swift`, whose own subtitle for that slot already
    /// promised "your profile now runs the Powerlevel10k treatment"
    /// before this actually existed. Only offered in `SettingsView`'s
    /// theme picker once unlocked; picking it otherwise isn't possible
    /// through the UI, but `colorScheme`/`accentColor` still resolve
    /// correctly if it's ever selected (defense in depth, not load-bearing).
    case powerlevel10k

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        case .powerlevel10k: "Powerlevel10k 🏆"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        // A terminal prompt theme reads as a dark terminal — the whole
        // point is the neon accent against a dark ground, not a light one.
        case .powerlevel10k: .dark
        }
    }

    /// `nil` lets the app fall back to the asset catalog's static
    /// `AccentColor` (every other theme) — only this one overrides it,
    /// applied at the root in `ProjectRApp`.
    var accentColor: Color? {
        switch self {
        case .system, .light, .dark: nil
        case .powerlevel10k: Color(red: 0.10, green: 0.95, blue: 0.55)
        }
    }
}
