import SwiftUI

/// Per-conversation chat theme, drawn from popular Neovim colorschemes —
/// stored as `conversations.theme` (plain string), shared between both
/// participants like Instagram's chat themes rather than a personal
/// per-user preference.
enum ChatTheme: String, CaseIterable, Identifiable {
    case `default`
    case tokyonight
    case catppuccin
    case gruvbox
    case dracula
    case nord
    case onedark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: "Default"
        case .tokyonight: "Tokyonight"
        case .catppuccin: "Catppuccin"
        case .gruvbox: "Gruvbox"
        case .dracula: "Dracula"
        case .nord: "Nord"
        case .onedark: "One Dark"
        }
    }

    struct Palette {
        let background: Color
        let myBubble: Color
        let theirBubble: Color
        let myText: Color
        let theirText: Color
        let accent: Color
    }

    var palette: Palette {
        switch self {
        case .default:
            Palette(
                background: Color(.systemBackground),
                myBubble: Color.accentColor,
                theirBubble: Color(.secondarySystemBackground),
                myText: .white,
                theirText: .primary,
                accent: Color.accentColor
            )
        case .tokyonight:
            Palette(
                background: Color(hex: 0x1a1b26),
                myBubble: Color(hex: 0x7aa2f7),
                theirBubble: Color(hex: 0x24283b),
                myText: Color(hex: 0x1a1b26),
                theirText: Color(hex: 0xc0caf5),
                accent: Color(hex: 0xbb9af7)
            )
        case .catppuccin:
            Palette(
                background: Color(hex: 0x1e1e2e),
                myBubble: Color(hex: 0xcba6f7),
                theirBubble: Color(hex: 0x313244),
                myText: Color(hex: 0x1e1e2e),
                theirText: Color(hex: 0xcdd6f4),
                accent: Color(hex: 0x89b4fa)
            )
        case .gruvbox:
            Palette(
                background: Color(hex: 0x282828),
                myBubble: Color(hex: 0xfe8019),
                theirBubble: Color(hex: 0x3c3836),
                myText: Color(hex: 0x282828),
                theirText: Color(hex: 0xebdbb2),
                accent: Color(hex: 0xfabd2f)
            )
        case .dracula:
            Palette(
                background: Color(hex: 0x282a36),
                myBubble: Color(hex: 0xbd93f9),
                theirBubble: Color(hex: 0x44475a),
                myText: Color(hex: 0x282a36),
                theirText: Color(hex: 0xf8f8f2),
                accent: Color(hex: 0xff79c6)
            )
        case .nord:
            Palette(
                background: Color(hex: 0x2e3440),
                myBubble: Color(hex: 0x88c0d0),
                theirBubble: Color(hex: 0x3b4252),
                myText: Color(hex: 0x2e3440),
                theirText: Color(hex: 0xeceff4),
                accent: Color(hex: 0x81a1c1)
            )
        case .onedark:
            Palette(
                background: Color(hex: 0x282c34),
                myBubble: Color(hex: 0x61afef),
                theirBubble: Color(hex: 0x21252b),
                myText: Color(hex: 0x282c34),
                theirText: Color(hex: 0xabb2bf),
                accent: Color(hex: 0x98c379)
            )
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
