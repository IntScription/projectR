import SwiftUI

/// Settings > Levels — the full 100-slot achievement ladder, one unlocked
/// every 100 levels. Unlock state is derived entirely client-side from the
/// profile's current level (see `Achievement`) — nothing here is fetched
/// beyond the level itself.
struct AchievementsListView: View {
    let profileID: UUID

    @State private var level: ProfileLevel?
    @State private var isLoading = true

    private var currentLevel: Int { level?.level ?? 0 }
    private var unlockedCount: Int { Achievement.unlocked(at: currentLevel).count }

    private var ranksInOrder: [String] {
        var seen = Set<String>()
        return Achievement.all.compactMap { seen.insert($0.rank).inserted ? $0.rank : nil }
    }

    var body: some View {
        List {
            if !isLoading {
                Section {
                    header
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            ForEach(ranksInOrder, id: \.self) { rank in
                Section(rank) {
                    ForEach(Achievement.all.filter { $0.rank == rank }) { achievement in
                        row(for: achievement)
                    }
                }
            }
        }
        .navigationTitle("Levels")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            level = await ProfileLevelService.fetch(profileID: profileID)
            isLoading = false
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("Level \(currentLevel)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("\(unlockedCount) of \(Achievement.all.count) achievements unlocked")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let next = Achievement.next(after: currentLevel) {
                VStack(spacing: 4) {
                    ProgressView(
                        value: Double(currentLevel % 100),
                        total: 100
                    )
                    .tint(next.color)
                    Text("\(next.level - currentLevel) levels to \"\(next.title)\"")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 40)
            } else {
                Text("Maxed out. Powerlevel10k engaged.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func row(for achievement: Achievement) -> some View {
        let isUnlocked = achievement.level <= currentLevel
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isUnlocked ? achievement.color.opacity(0.18) : Color(.tertiarySystemFill))
                Image(systemName: isUnlocked ? achievement.icon : "lock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isUnlocked ? achievement.color : .secondary)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isUnlocked ? .primary : .secondary)
                Text(achievement.subtitle)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(achievement.color)
            } else {
                Text("Lv \(achievement.level)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .opacity(isUnlocked ? 1 : 0.6)
    }
}
