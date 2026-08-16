import PhotosUI
import Supabase
import SwiftUI

/// Marker route for pushing Notifications from Profile's own NavigationStack
/// — Notifications lives inside Profile rather than as its own tab.
private struct NotificationsRoute: Hashable {}

/// Marker route for pushing the portfolio builder from Profile's header
/// quick actions — same reasoning as `NotificationsRoute`.
private struct PortfolioRoute: Hashable {}

struct ProfileView: View {
    @Binding var profile: Profile
    let auth: AuthViewModel

    @State private var isPresentingSettings = false
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var selectedBannerItem: PhotosPickerItem?
    @State private var isUploadingBanner = false
    @State private var unreadNotificationCount = 0
    @State private var isGitHubVerified = false
    @State private var myStories: [Story] = []
    @State private var isPresentingStoryCaptureMenu = false
    @State private var capturedStoryMedia: Data?
    @State private var capturedStoryKind: StoryMediaKind = .image
    @State private var isPresentingStoryComposer = false
    @State private var isPresentingStoryViewer = false
    @State private var selectedTab: ProfileContentTab = .projects
    @State private var currentLevel = 0
    @State private var justUnlockedAchievement: Achievement?

    /// Achievements only enters the tab picker once there's at least one
    /// to show — mirrors the existing "hide the Forge tab until GitHub is
    /// connected" pattern rather than offering a permanently-empty tab.
    private var visibleTabs: [ProfileContentTab] {
        ProfileContentTab.allCases.filter { $0 != .achievements || currentLevel >= 100 }
    }

    var body: some View {
        // Only the selected tab's content scrolls — the banner, avatar,
        // bio, links, and level badge stay put above it instead of
        // sliding away, so switching tabs (or scrolling a long list)
        // never loses your place in the identity section above it.
        VStack(spacing: 0) {
            header
            HighlightsRailView(owner: profile)
            ProfileTabPicker(selection: $selectedTab, tabs: visibleTabs)
            ScrollView {
                tabContent
                    .padding(.top, 12)
            }
        }
        // The banner runs edge-to-edge from the very top, so the nav bar
        // itself is hidden entirely rather than left as an empty strip
        // above it — this is the root of Profile's own NavigationStack, so
        // there's no back button being lost. The actions that used to live
        // in the toolbar (share/notifications/settings) now sit inline in
        // the header, on the username's row.
        .floatingTabBarClearance()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: NotificationsRoute.self) { _ in NotificationsView() }
        .navigationDestination(for: PortfolioRoute.self) { _ in PortfolioBuilderView(profile: profile) }
        .navigationDestination(for: UUID.self) { ProjectDetailView(projectID: $0) }
        .navigationDestination(for: CreatorRoute.self) { CreatorProfileView(userID: $0.userID) }
        .sheet(isPresented: $isPresentingSettings) {
            NavigationStack {
                SettingsView(profile: $profile, auth: auth)
            }
        }
        .sheet(item: $justUnlockedAchievement) { achievement in
            LevelUpSheet(achievement: achievement, profile: $profile)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.success, trigger: justUnlockedAchievement) { _, newValue in newValue != nil }
        .task { await refreshUnreadCount() }
        .task(id: profile.id) { await subscribeToNewNotifications() }
        .task(id: profile.id) {
            isGitHubVerified = await GitHubService.isConnected(profileID: profile.id)
        }
        // Profile is a persistent tab (kept mounted once visited), so
        // without this, connecting/disconnecting GitHub from Settings
        // while already on this tab wouldn't flip the verified tick
        // until the next full relaunch — the `.task(id:)` above only
        // reruns when `profile.id` itself changes, never for the same
        // profile.
        .onReceive(NotificationCenter.default.publisher(for: .gitHubDidConnect)) { _ in
            isGitHubVerified = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .gitHubDidDisconnect)) { _ in
            isGitHubVerified = false
        }
        .task(id: profile.id) { await loadMyStories() }
    }

    /// Detects a level-up entirely on-device by comparing against the
    /// last tier this profile was seen at (stored per-profile, since
    /// `LevelBadge` already fetches the real level server-side — this
    /// just notices when that number crossed a 100-boundary since last
    /// time). The very first time a tier is ever recorded for a profile
    /// on this device, it's stored silently rather than celebrated — an
    /// existing high-level account opening the updated app for the first
    /// time shouldn't get a fake "you just leveled up."
    private func handleLevelFetched(_ level: ProfileLevel) {
        currentLevel = level.level
        let key = "lastSeenLevelTier-\(profile.id.uuidString)"
        let newTier = level.level / 100
        guard let lastSeenTier = UserDefaults.standard.object(forKey: key) as? Int else {
            UserDefaults.standard.set(newTier, forKey: key)
            return
        }
        guard newTier > lastSeenTier else { return }
        UserDefaults.standard.set(newTier, forKey: key)
        justUnlockedAchievement = Achievement.all.first { $0.level == newTier * 100 }
    }

    private func loadMyStories() async {
        let items: [StoryFeedItem] =
            (try? await SupabaseManager.shared.client
                .from("active_stories_feed")
                .select()
                .eq("author_id", value: profile.id)
                .order("created_at")
                .execute()
                .value) ?? []
        myStories = items.map {
            Story(
                id: $0.id, authorID: $0.authorID, mediaURL: $0.mediaURL, mediaType: $0.mediaType,
                createdAt: $0.createdAt, expiresAt: $0.expiresAt)
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .projects: ProjectsTabContent(ownerID: profile.id)
        case .posts: PostsTabContent(ownerID: profile.id)
        case .notes: NotesTabContent(authorID: profile.id)
        case .saved: SavedTabContent()
        case .achievements: AchievementsTabContent(currentLevel: currentLevel, profile: $profile)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                bannerView
                avatarView
                    .offset(x: 16, y: 44)
            }
            .padding(.bottom, 48)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 12) {
                        HStack(spacing: 4) {
                            Text(profile.username)
                                .font(.title2.bold())
                            if isGitHubVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityLabel("Verified")
                            }
                        }
                        Spacer(minLength: 8)
                        headerActions
                    }

                    HStack(spacing: 8) {
                        Text(profile.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let role = profile.role, !role.isEmpty {
                            RoleBadge(text: role)
                        }
                    }
                }

                if let bio = profile.bio, !bio.isEmpty {
                    Text(bio)
                }

                ProfileLinksSection(links: profile.links)

                // Skills are entirely auto-computed from projects (see
                // LevelBadge / LevelDashboardView) — no manual "type your
                // skills" field, so there's nothing to display separately
                // here; tapping the badge below is the one place to see them.
                LevelBadge(profileID: profile.id, onLevelFetched: handleLevelFetched)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    /// Sized to sit comfortably on the username's own line — `.title3`
    /// against the username's `.title2.bold()` reads as one coherent row
    /// instead of oversized nav-bar icons dropped into content.
    private var headerActions: some View {
        HStack(spacing: 18) {
            ShareLink(item: ShareLinks.profile(username: profile.username)) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share profile")

            NavigationLink(value: PortfolioRoute()) {
                Image(systemName: "doc.richtext")
            }
            .accessibilityLabel("Portfolio PDF")

            NavigationLink(value: NotificationsRoute()) {
                Image(systemName: "bell")
                    .overlay(alignment: .topTrailing) {
                        if unreadNotificationCount > 0 {
                            Circle()
                                .fill(.red)
                                .frame(width: 7, height: 7)
                                .offset(x: 3, y: -3)
                        }
                    }
            }
            .accessibilityLabel(unreadNotificationCount > 0 ? "Notifications, unread" : "Notifications")

            Button {
                isPresentingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }
        .font(.title3)
        .foregroundStyle(.primary)
    }

    private var bannerView: some View {
        PhotosPicker(selection: $selectedBannerItem, matching: .images) {
            ZStack {
                AsyncImage(url: profile.bannerURL.flatMap(URL.init)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.1)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 130)
                .clipped()

                if isUploadingBanner {
                    Color.black.opacity(0.35)
                    ProgressView().tint(.white)
                }
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .padding(10)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change banner photo")
        .task(id: selectedBannerItem) { await updateBanner() }
    }

    /// Tapping the avatar itself opens your story (or the capture flow if
    /// you have none) — the pencil badge is its own separate tap target
    /// for changing the photo, so the two actions don't fight over one
    /// hit area the way a single `PhotosPicker` button used to cover both.
    private var avatarView: some View {
        Button {
            if myStories.isEmpty {
                isPresentingStoryCaptureMenu = true
            } else {
                isPresentingStoryViewer = true
            }
        } label: {
            ZStack {
                StoryRingAvatar(
                    avatarURL: profile.avatarURL, placeholderInitial: profile.displayName,
                    diameter: 84, ringState: myStories.isEmpty ? .none : .seen)

                if isUploadingAvatar {
                    Circle().fill(.black.opacity(0.35)).frame(width: 84, height: 84)
                    ProgressView().tint(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(myStories.isEmpty ? "Add to your story" : "View your story")
        .overlay(alignment: .bottomTrailing) {
            PhotosPicker(selection: $selectedAvatarItem, matching: .images) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white, Color.accentColor)
                    .background(Circle().fill(.white))
            }
            .accessibilityLabel("Change profile photo")
        }
        .storyCaptureSourceMenu(isPresented: $isPresentingStoryCaptureMenu) { data, kind in
            capturedStoryMedia = data
            capturedStoryKind = kind
            isPresentingStoryComposer = true
        }
        .fullScreenCover(isPresented: $isPresentingStoryComposer) {
            if let capturedStoryMedia {
                StoryComposerView(
                    uploaderID: profile.id, mediaData: capturedStoryMedia, mediaKind: capturedStoryKind
                ) {
                    Task { await loadMyStories() }
                }
            }
        }
        .fullScreenCover(isPresented: $isPresentingStoryViewer) {
            StoryViewerView(
                stories: myStories, startIndex: 0, authorID: profile.id, authorUsername: profile.username,
                authorDisplayName: profile.displayName, authorAvatarURL: profile.avatarURL, isOwnStory: true,
                onDeleted: { _ in Task { await loadMyStories() } })
        }
        .task(id: selectedAvatarItem) { await updateAvatar() }
    }

    private func refreshUnreadCount() async {
        unreadNotificationCount =
            (try? await Engagement.count(table: "notifications", filters: ["is_read": false]))
            ?? 0
    }

    /// Re-counts on every new notification rather than incrementing
    /// locally — a single source of truth avoids the badge ever drifting
    /// out of sync with what `NotificationsView` actually shows.
    private func subscribeToNewNotifications() async {
        let channel = SupabaseManager.shared.client.channel("notifications:\(profile.id.uuidString)")
        let changes = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "notifications",
            filter: .eq("recipient_id", value: profile.id.uuidString)
        )
        await channel.subscribe()

        for await _ in changes {
            await refreshUnreadCount()
        }
    }

    /// Fixed filename (not a random one, unlike project media) plus
    /// `upsert: true` so re-uploading replaces the same storage object
    /// instead of piling up orphaned files every time someone changes
    /// their photo.
    private func updateAvatar() async {
        guard let selectedAvatarItem, let data = try? await selectedAvatarItem.loadTransferable(type: Data.self)
        else { return }

        isUploadingAvatar = true
        defer { isUploadingAvatar = false }

        do {
            let path = "\(profile.id)/avatar.jpg"
            let storage = SupabaseManager.shared.client.storage.from(SupabaseBucket.avatars)
            try await storage.upload(
                path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
            // Same fixed path every upload, so the URL string alone never
            // changes — append a cache-busting query param or AsyncImage
            // (and any HTTP cache in between) keeps showing the old bytes.
            let url = try storage.getPublicURL(path: path).absoluteString
                + "?v=\(Int(Date().timeIntervalSince1970))"

            let updated: Profile =
                try await SupabaseManager.shared.client
                .from("profiles")
                .update(["avatar_url": url])
                .eq("id", value: profile.id)
                .select()
                .single()
                .execute()
                .value
            profile = updated
        } catch {
            // Best-effort — the picker UI already resets itself either way.
            AppLogger.upload.error("Profile image upload failed: \(error.localizedDescription)")
        }
    }

    private func updateBanner() async {
        guard let selectedBannerItem, let data = try? await selectedBannerItem.loadTransferable(type: Data.self)
        else { return }

        isUploadingBanner = true
        defer { isUploadingBanner = false }

        do {
            let path = "\(profile.id)/banner.jpg"
            let storage = SupabaseManager.shared.client.storage.from(SupabaseBucket.avatars)
            try await storage.upload(
                path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
            let url = try storage.getPublicURL(path: path).absoluteString
                + "?v=\(Int(Date().timeIntervalSince1970))"

            let updated: Profile =
                try await SupabaseManager.shared.client
                .from("profiles")
                .update(["banner_url": url])
                .eq("id", value: profile.id)
                .select()
                .single()
                .execute()
                .value
            profile = updated
        } catch {
            // Best-effort — the picker UI already resets itself either way.
            AppLogger.upload.error("Profile image upload failed: \(error.localizedDescription)")
        }
    }
}
