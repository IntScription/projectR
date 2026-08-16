import SwiftUI

/// Static, computed-client-side achievement ladder — one slot every 100
/// levels across the 1-10,000 range (100 total). Unlocked state is derived
/// purely from a profile's current `level` (already known from
/// `profile_levels`), so this needs no database table of its own: nothing
/// to seed, nothing that can drift out of sync with the level formula.
///
/// 10 ranks of 10 tiers each. The final slot (level 10,000, max) is the
/// "Powerlevel10k" achievement — a nod to the popular Zsh prompt theme of
/// the same name, and this app's one cosmetic reward for maxing out.
struct Achievement: Identifiable, Hashable {
    var level: Int
    var rank: String
    var tier: Int
    var title: String
    var subtitle: String
    var icon: String
    var color: Color
    var reward: AchievementReward

    var id: Int { level }
    var isMax: Bool { level == Achievement.maxLevel }

    static let maxLevel = 10_000

    private static let ranks: [(name: String, icon: String, color: Color)] = [
        ("Rookie", "leaf.fill", .mint),
        ("Hobbyist", "hammer.fill", .teal),
        ("Contributor", "person.2.fill", .cyan),
        ("Builder", "building.2.fill", .blue),
        ("Shipper", "shippingbox.fill", .indigo),
        ("Engineer", "gearshape.fill", .purple),
        ("Architect", "building.columns.fill", .pink),
        ("Specialist", "star.fill", .orange),
        ("Principal", "crown.fill", .yellow),
        ("Legend", "trophy.fill", .red),
    ]

    private static let romanNumerals = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

    /// All 100 achievements, level 100 through 10,000, ascending.
    static let all: [Achievement] = {
        var items: [Achievement] = []
        for rankIndex in 0..<10 {
            let rank = ranks[rankIndex]
            for tier in 0..<10 {
                let level = rankIndex * 1_000 + (tier + 1) * 100
                let isFinal = level == maxLevel
                items.append(
                    Achievement(
                        level: level,
                        rank: rank.name,
                        tier: tier + 1,
                        title: isFinal ? "Powerlevel10k" : "\(rank.name) \(romanNumerals[tier])",
                        subtitle: isFinal
                            ? "Maxed out. Your profile now runs the Powerlevel10k treatment."
                            : "Reach level \(level).",
                        icon: isFinal ? "terminal.fill" : rank.icon,
                        color: rank.color,
                        // The first achievement gets a banner; the very
                        // last one (this system's one other real reward)
                        // unlocks the Powerlevel10k theme — the subtitle
                        // above already promised this before it existed.
                        reward: level == 100 ? .banner : (isFinal ? .theme : .none)
                    )
                )
            }
        }
        return items
    }()

    static func unlocked(at currentLevel: Int) -> [Achievement] {
        all.filter { $0.level <= currentLevel }
    }

    static func next(after currentLevel: Int) -> Achievement? {
        all.first { $0.level > currentLevel }
    }

    static func latestUnlocked(at currentLevel: Int) -> Achievement? {
        unlocked(at: currentLevel).last
    }
}

/// What earning an achievement actually gives you, beyond a checkmark in
/// the collection. `.none` (most achievements, for now) still shows in the
/// collection and still triggers the level-up celebration — it just has
/// no applyable action attached.
enum AchievementReward: Hashable {
    case none
    case banner
    /// Unlocks `AppTheme.powerlevel10k` as a selectable option in
    /// Settings' theme picker — applying it just writes to the same
    /// `@AppStorage("appTheme")` key the picker itself uses, no network
    /// call, no error path.
    case theme
}
