import SwiftUI

/// Icon-only, Instagram-profile-style content switcher. `Saved` is
/// private (bookmarks only ever belong to the viewer), so it's only ever
/// offered on your own profile — `CreatorProfileView` passes projects,
/// posts, and notes only. `Notes` is public like everything else.
enum ProfileContentTab: CaseIterable {
    case projects, posts, notes, saved, achievements

    var icon: String {
        switch self {
        case .projects: "square.grid.2x2"
        case .posts: "rectangle.stack"
        case .notes: "note.text"
        case .saved: "bookmark"
        case .achievements: "trophy.fill"
        }
    }

    /// The icons carry no visible text — this is what VoiceOver actually
    /// announces, since without it there's nothing to distinguish
    /// "square.grid.2x2" from any other icon.
    var accessibilityLabel: String {
        switch self {
        case .projects: "Projects"
        case .posts: "Posts"
        case .notes: "Notes"
        case .saved: "Saved"
        case .achievements: "Achievements"
        }
    }
}

struct ProfileTabPicker: View {
    @Binding var selection: ProfileContentTab
    let tabs: [ProfileContentTab]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 19, weight: selection == tab ? .semibold : .regular))
                        Rectangle()
                            .fill(selection == tab ? Color.primary : Color.clear)
                            .frame(height: 2)
                    }
                    .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.accessibilityLabel)
                .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
            }
        }
        .padding(.top, 4)
    }
}

/// Note: these render directly into the profile's own `ScrollView` via
/// `LazyVStack`/`LazyVGrid` rather than wrapping a `List` — a `List`
/// nested inside a `ScrollView` is a known-broken combination already
/// avoided elsewhere in this app (see `ProjectListView`'s header comment).
struct ProjectsTabContent: View {
    let ownerID: UUID

    @State private var projects: [Project] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading && projects.isEmpty {
                ProgressView().padding(.top, 60)
            } else if projects.isEmpty {
                ProfileEmptyState(
                    icon: "square.grid.2x2", title: "No projects yet",
                    message: "Projects you create show up here.")
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(projects) { project in
                        NavigationLink(value: project.id) {
                            ProjectSummaryRow(project: project)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        projects =
            (try? await SupabaseManager.shared.client
                .from("projects")
                .select()
                .eq("owner_id", value: ownerID)
                .order("created_at", ascending: false)
                .execute()
                .value) ?? []
    }
}

struct ProjectSummaryRow: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name).font(.headline)
            if let description = project.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(project.status.rawValue.capitalized)
                .font(.caption.bold())
                .foregroundStyle(.orange)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct PostsTabContent: View {
    let ownerID: UUID

    @State private var items: [ProfileUpdateFeedItem] = []
    @State private var isLoading = false

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView().padding(.top, 60)
            } else if items.isEmpty {
                ProfileEmptyState(
                    icon: "rectangle.stack", title: "No posts yet",
                    message: "Updates you post on your projects show up here.")
            } else {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(items) { item in
                        NavigationLink(value: item.projectID) {
                            PostGridCell(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        items =
            (try? await SupabaseManager.shared.client
                .from("profile_updates_feed")
                .select()
                .eq("owner_id", value: ownerID)
                .order("created_at", ascending: false)
                .limit(60)
                .execute()
                .value) ?? []
    }
}

/// A little more visual than a bare `Text` — an icon in a soft tinted
/// circle plus a title/subtitle — so an empty tab reads as "nothing here
/// yet" rather than a blank, unfinished-looking gap.
struct ProfileEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.top, 60)
        .padding(.bottom, 40)
    }
}

private struct PostGridCell: View {
    let item: ProfileUpdateFeedItem

    var body: some View {
        ZStack {
            if let url = item.mediaURL.flatMap(URL.init) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.1)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay {
            Text(item.body)
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(6)
                .lineLimit(4)
        }
    }
}

/// Public, unlike Saved — short text notes for whichever profile is being
/// viewed, own or someone else's.
struct NotesTabContent: View {
    let authorID: UUID

    @State private var notes: [Note] = []
    @State private var isLoading = false
    @State private var notePendingDeleteID: UUID?
    @State private var didDeleteNote = false

    private var currentUserID: UUID? {
        SupabaseManager.shared.client.auth.currentSession?.user.id
    }

    var body: some View {
        Group {
            if isLoading && notes.isEmpty {
                ProgressView().padding(.top, 60)
            } else if notes.isEmpty {
                ProfileEmptyState(
                    icon: "note.text", title: "No notes yet",
                    message: "Short, project-independent thoughts show up here.")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(notes) { note in
                        NoteCard(note: note, isOwn: note.authorID == currentUserID) {
                            notePendingDeleteID = note.id
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(
                get: { notePendingDeleteID != nil }, set: { if !$0 { notePendingDeleteID = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await deleteNote() } }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: didDeleteNote) { _, newValue in newValue }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        notes =
            (try? await SupabaseManager.shared.client
                .from("notes")
                .select()
                .eq("author_id", value: authorID)
                .order("created_at", ascending: false)
                .execute()
                .value) ?? []
    }

    private func deleteNote() async {
        guard let noteID = notePendingDeleteID else { return }
        notePendingDeleteID = nil
        do {
            try await SupabaseManager.shared.client
                .from("notes")
                .delete()
                .eq("id", value: noteID)
                .execute()
            notes.removeAll { $0.id == noteID }
            didDeleteNote = true
            AnalyticsService.track("note_deleted")
        } catch {
            CrashReporter.capture(error, context: "delete_note")
        }
    }
}

private struct NoteCard: View {
    let note: Note
    var isOwn: Bool = false
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(note.body)
                    .font(.subheadline)
                Text(note.createdAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isOwn {
                Button {
                    onDelete?()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete note")
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Own-profile only — `saved_projects_feed`'s RLS scoping means this
/// always returns just the caller's own saves regardless of who's asked.
struct SavedTabContent: View {
    @State private var projects: [DiscoverProject] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading && projects.isEmpty {
                ProgressView().padding(.top, 60)
            } else if projects.isEmpty {
                ProfileEmptyState(
                    icon: "bookmark", title: "Nothing saved yet",
                    message: "Tap the bookmark icon on a project to save it here.")
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(projects) { project in
                        FeedPostCard(project: project)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        projects =
            (try? await SupabaseManager.shared.client
                .from("saved_projects_feed")
                .select()
                .order("saved_at", ascending: false)
                .execute()
                .value) ?? []
    }
}

/// A game-style badge collection rather than the plain settings list
/// `AchievementsListView` already has — unlocked achievements show in
/// full color, locked ones desaturated with a small lock badge and
/// "Unlock at level N" in place of their title. `profile` is nil when
/// viewing someone else's profile (`CreatorProfileView`) — the reward
/// "Use this" action only ever applies to your own account, so it's
/// simply not offered there; the collection itself stays public either
/// way, like Notes.
struct AchievementsTabContent: View {
    let currentLevel: Int
    var profile: Binding<Profile>?

    @State private var selectedAchievement: Achievement?

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 22) {
            ForEach(Achievement.all) { achievement in
                let isUnlocked = achievement.level <= currentLevel
                Button {
                    selectedAchievement = achievement
                } label: {
                    AchievementTile(achievement: achievement, isUnlocked: isUnlocked)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .sheet(item: $selectedAchievement) { achievement in
            AchievementDetailSheet(
                achievement: achievement, isUnlocked: achievement.level <= currentLevel, profile: profile
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct AchievementTile: View {
    let achievement: Achievement
    let isUnlocked: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(
                        isUnlocked
                            ? AnyShapeStyle(achievement.color.gradient)
                            : AnyShapeStyle(Color(.tertiarySystemFill))
                    )
                    .overlay {
                        Image(systemName: achievement.icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(isUnlocked ? .white : Color.secondary)
                    }
                    .saturation(isUnlocked ? 1 : 0)

                if !isUnlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Color.secondary, in: Circle())
                        .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                }
            }
            .frame(width: 60, height: 60)

            Text(isUnlocked ? achievement.title : "Locked")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isUnlocked ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(isUnlocked ? achievement.rank : "Unlock at level \(achievement.level)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct AchievementDetailSheet: View {
    let achievement: Achievement
    let isUnlocked: Bool
    var profile: Binding<Profile>?

    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @State private var isApplying = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        isUnlocked
                            ? AnyShapeStyle(achievement.color.gradient)
                            : AnyShapeStyle(Color(.tertiarySystemFill))
                    )
                Image(systemName: isUnlocked ? achievement.icon : "lock.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(isUnlocked ? .white : Color.secondary)
            }
            .frame(width: 84, height: 84)
            .padding(.top, 8)

            VStack(spacing: 4) {
                Text(isUnlocked ? achievement.title : "Locked")
                    .font(.title3.bold())
                Text(isUnlocked ? achievement.subtitle : "Unlock at level \(achievement.level)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if isUnlocked, achievement.reward == .banner, let profile {
                AchievementBannerArtView(achievement: achievement)
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }

                Button {
                    Task { await applyReward(profile) }
                } label: {
                    if isApplying {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Use this").fontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(achievement.color)
                .controlSize(.large)
                .disabled(isApplying)
            } else if isUnlocked, achievement.reward == .theme {
                Button {
                    appThemeRaw = AppTheme.powerlevel10k.rawValue
                } label: {
                    Text(appThemeRaw == AppTheme.powerlevel10k.rawValue ? "Applied" : "Use this")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(achievement.color)
                .controlSize(.large)
                .disabled(appThemeRaw == AppTheme.powerlevel10k.rawValue)
            }

            Spacer()
        }
        .padding(24)
    }

    private func applyReward(_ profile: Binding<Profile>) async {
        isApplying = true
        errorMessage = nil
        defer { isApplying = false }
        do {
            try await AchievementReward_Art.applyAsBanner(achievement, profile: profile)
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}
