import SwiftUI

/// Tappable badge shown on a profile header — opens the full dashboard.
/// The level/skill data is scored server-side by a rule-based Postgres
/// function from real project signals (tech stack, shipped work, updates,
/// engagement), not an LLM call — see `refresh_profile_level` in
/// `20260813110000_profile_upgrades.sql`.
struct LevelBadge: View {
    let profileID: UUID
    /// Lets a caller (own-profile `ProfileView`, to detect a level-up and
    /// reveal the Achievements tab) observe what this badge already
    /// fetches, instead of duplicating the same RPC call a second time.
    var onLevelFetched: ((ProfileLevel) -> Void)?

    @State private var level: ProfileLevel?
    @State private var isPresentingDashboard = false

    private var isMaxLevel: Bool { (level?.level ?? 0) >= Achievement.maxLevel }

    var body: some View {
        Button {
            isPresentingDashboard = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isMaxLevel ? "terminal.fill" : "chart.bar.fill")
                Text(level.map { "Level \($0.level) · \($0.levelLabel)" } ?? "Level")
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                if isMaxLevel {
                    Capsule().fill(
                        AngularGradient(colors: [.orange, .pink, .purple, .blue, .cyan, .orange], center: .center)
                            .opacity(0.22)
                    )
                } else {
                    Capsule().fill(Color.accentColor.opacity(0.12))
                }
            }
            .foregroundStyle(isMaxLevel ? Color.orange : Color.accentColor)
        }
        .buttonStyle(.plain)
        .task {
            level = await ProfileLevelService.fetch(profileID: profileID)
            if let level { onLevelFetched?(level) }
        }
        .sheet(isPresented: $isPresentingDashboard) {
            LevelDashboardView(profileID: profileID)
        }
    }
}

struct LevelDashboardView: View {
    let profileID: UUID

    @State private var level: ProfileLevel?
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let level {
                    content(for: level)
                } else if isLoading {
                    ProgressView()
                } else {
                    ContentUnavailableView("No data yet", systemImage: "chart.bar")
                }
            }
            .navigationTitle("Growth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func content(for level: ProfileLevel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if level.level >= Achievement.maxLevel {
                    powerlevel10kHeader()
                } else {
                    standardHeader(for: level)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Overview")
                        .font(.headline)
                    Text(level.summary)
                        .foregroundStyle(.secondary)
                }

                if !level.breakdown.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Strengths & weaknesses")
                            .font(.headline)
                        RadarChartView(
                            axes: level.breakdown.map {
                                .init(name: $0.name, value: Double($0.score), color: Self.componentColor(for: $0.name))
                            }
                        )
                        .frame(maxWidth: .infinity)
                    }
                }

                if !level.breakdown.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How this is calculated")
                            .font(.headline)
                        VStack(spacing: 10) {
                            ForEach(level.breakdown) { component in
                                breakdownRow(component)
                            }
                        }
                        Text("Score = Σ (component × its weight). Weights sum to 100%.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if !level.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("How to level up")
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(level.notes, id: \.self) { note in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "arrow.up.forward.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                    Text(note)
                                        .font(.subheadline)
                                }
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                if !level.skills.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Skills")
                            .font(.headline)
                        FlowLayout(spacing: 8) {
                            ForEach(level.skills) { skill in
                                skillChip(skill)
                            }
                        }
                    }
                }

                Text("Recomputed automatically from your projects, updates, and engagement — updates at least once a day.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
    }

    private func standardHeader(for level: ProfileLevel) -> some View {
        VStack(spacing: 14) {
            ZStack {
                LevelProgressRing(
                    progress: Double(level.level) / Double(Achievement.maxLevel),
                    style: AnyShapeStyle(
                        AngularGradient(
                            colors: [Color.accentColor, .pink, Color.accentColor],
                            center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)
                        )
                    )
                )
                .frame(width: 170, height: 170)
                VStack(spacing: 4) {
                    Text("\(level.level)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text(level.levelLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            achievementProgress(for: level)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func achievementProgress(for level: ProfileLevel) -> some View {
        VStack(spacing: 6) {
            if let latest = Achievement.latestUnlocked(at: level.level) {
                HStack(spacing: 6) {
                    Image(systemName: latest.icon)
                        .foregroundStyle(latest.color)
                    Text(latest.title)
                        .font(.caption.weight(.semibold))
                }
            }
            if let next = Achievement.next(after: level.level) {
                VStack(spacing: 3) {
                    ProgressView(value: Double(level.level % 100), total: 100)
                        .tint(next.color)
                        .frame(maxWidth: 160)
                    Text("\(next.level - level.level) to \"\(next.title)\"")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// Cosmetic reward at the max level (10,000) — a nod to the
    /// Powerlevel10k Zsh prompt theme, styled as powerline-style prompt
    /// segments. Purely visual; the underlying level/score computation is
    /// unchanged at max, same as every level below it.
    private func powerlevel10kHeader() -> some View {
        VStack(spacing: 14) {
            ZStack {
                LevelProgressRing(
                    progress: 1,
                    style: AnyShapeStyle(
                        AngularGradient(colors: [.orange, .pink, .purple, .blue, .cyan, .orange], center: .center)
                    )
                )
                .frame(width: 170, height: 170)
                VStack(spacing: 4) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("10000")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("MAX LEVEL")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            powerlineStrip
            Text("Powerlevel10k engaged — every project signal maxed out.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var powerlineStrip: some View {
        HStack(spacing: 6) {
            powerlineSegment("MAX", .orange)
            powerlineChevron
            powerlineSegment("LV 10000", .pink)
            powerlineChevron
            powerlineSegment("100%", .purple)
        }
    }

    private var powerlineChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.secondary)
    }

    private func powerlineSegment(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.gradient, in: Capsule())
    }

    private func breakdownRow(_ component: ProfileLevel.Component) -> some View {
        let color = Self.componentColor(for: component.name)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(component.name)
                    .font(.subheadline.weight(.medium))
                Text("\(component.weight)% weight")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(component.score)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
            }
            ProgressView(value: Double(component.score), total: 100)
                .tint(color)
        }
    }

    /// A distinct, meaningful color per scoring component instead of one
    /// flat accent everywhere — used consistently across the breakdown
    /// bars and the radar chart so the same component always reads the
    /// same color in both places.
    private static func componentColor(for name: String) -> Color {
        switch name {
        case "Shipping rate": .green
        case "Tech breadth": .blue
        case "Activity": .purple
        case "Engagement": .pink
        case "Portfolio size": .teal
        default: .accentColor
        }
    }

    private func skillChip(_ skill: ProfileLevel.Skill) -> some View {
        HStack(spacing: 6) {
            Text(skill.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
            Text("Lv \(skill.level)")
                .font(.caption2.weight(.bold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.2), in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
        // FlowLayout's sizeThatFits/placeSubviews two-pass wrapping can
        // disagree on available width at row edges — `.fixedSize()` above
        // guarantees the chip always renders at its true intrinsic width
        // instead of getting clipped to whatever width was proposed.
        .fixedSize()
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        level = await ProfileLevelService.fetch(profileID: profileID)
    }
}

/// Circular progress indicator for overall level (progress toward 10,000).
/// `style` accepts either a flat color or a gradient so the max-level
/// Powerlevel10k treatment can swap in an `AngularGradient` without a
/// second component.
private struct LevelProgressRing: View {
    var progress: Double
    var style: AnyShapeStyle
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(progress, 1)))
                .stroke(style, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

