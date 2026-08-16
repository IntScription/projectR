import SwiftUI

/// Shown once, right when `ProfileView` detects a level-up (see its
/// `LevelBadge(onLevelFetched:)` callback) — same fixed-bottom-CTA sheet
/// shape as `ForgeIntroSheet`. What the primary button says and does
/// depends entirely on `achievement.reward`: a real applyable reward
/// (banner art today) gets "Use this"; no reward just gets "Nice!".
struct LevelUpSheet: View {
    let achievement: Achievement
    @Binding var profile: Profile

    @Environment(\.dismiss) private var dismiss
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @State private var isApplying = false
    @State private var errorMessage: String?

    private var rewardButtonTitle: String {
        switch achievement.reward {
        case .banner, .theme: "Use this"
        case .none: "Nice!"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    if achievement.reward == .banner {
                        AchievementBannerArtView(achievement: achievement)
                            .frame(height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08))
                            )
                    } else if achievement.reward == .theme {
                        Powerlevel10kPreview()
                            .frame(height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(24)
            }

            VStack(spacing: 10) {
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                Button {
                    switch achievement.reward {
                    case .banner: Task { await applyBanner() }
                    case .theme: applyTheme()
                    case .none: dismiss()
                    }
                } label: {
                    Group {
                        if isApplying {
                            ProgressView().tint(.white)
                        } else {
                            Text(rewardButtonTitle).fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(achievement.color)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(isApplying)

                if achievement.reward != .none {
                    Button("Maybe later") { dismiss() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(achievement.color.gradient)
                Image(systemName: achievement.icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 84, height: 84)
            .shadow(color: achievement.color.opacity(0.35), radius: 16, y: 6)

            VStack(spacing: 4) {
                Text("Level \(achievement.level)!")
                    .font(.title.bold())
                Text(achievement.title)
                    .font(.headline)
                    .foregroundStyle(achievement.color)
            }

            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var headerSubtitle: String {
        switch achievement.reward {
        case .banner: "You earned a new profile banner."
        case .theme: "You unlocked the Powerlevel10k theme — a new option in Settings."
        case .none: achievement.subtitle
        }
    }

    private func applyBanner() async {
        isApplying = true
        errorMessage = nil
        defer { isApplying = false }
        do {
            try await AchievementReward_Art.applyAsBanner(achievement, profile: $profile)
            dismiss()
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func applyTheme() {
        appThemeRaw = AppTheme.powerlevel10k.rawValue
        dismiss()
    }
}

/// A small, self-contained preview of what picking this theme actually
/// looks like — dark ground, the same neon accent `AppTheme.powerlevel10k`
/// applies everywhere else, rendered right here so this doesn't depend on
/// the environment's real accent color (which won't be Powerlevel10k's
/// yet at the moment this sheet is shown, before the user has tapped
/// "Use this").
private struct Powerlevel10kPreview: View {
    var body: some View {
        ZStack {
            Color.black
            HStack(spacing: 10) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 28, weight: .semibold))
                Text("Powerlevel10k")
                    .font(.system(.title3, design: .monospaced).weight(.bold))
            }
            .foregroundStyle(AppTheme.powerlevel10k.accentColor ?? .green)
        }
    }
}
