import SwiftUI

/// Navigation value for pushing another user's profile — kept distinct from
/// the plain `UUID` used for project pushes so both can live in the same
/// `NavigationStack` without colliding.
struct CreatorRoute: Hashable {
    let userID: UUID
}

/// A read-only view of someone else's profile — no edit/create/sign-out
/// affordances, just their projects/posts and a Follow button. `ProfileView`
/// is the equivalent view for your own profile (which additionally gets a
/// Saved tab — bookmarks are private, so they never show up here).
struct CreatorProfileView: View {
    let userID: UUID

    @State private var profile: Profile?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var chatRoute: ChatRoute?
    @State private var isGitHubVerified = false
    @State private var selectedTab: ProfileContentTab = .projects
    @State private var isBlocked = false
    @State private var haveIBlocked = false
    @State private var isPresentingReport = false
    @State private var isPresentingBlockConfirm = false
    @State private var theirStories: [Story] = []
    @State private var theirStoriesHaveUnseen = false
    @State private var isPresentingStoryViewer = false
    @State private var currentLevel = 0

    /// Public like Notes — achievements are meant to be seen — but still
    /// only shown once there's at least one to see, same as own-profile.
    private var visibleTabs: [ProfileContentTab] {
        [.projects, .posts, .notes] + (currentLevel >= 100 ? [.achievements] : [])
    }

    private var isOwnProfile: Bool {
        SupabaseManager.shared.client.auth.currentSession?.user.id == userID
    }

    var body: some View {
        Group {
            if let profile {
                ScrollView {
                    VStack(spacing: 0) {
                        header(for: profile)
                        HighlightsRailView(owner: profile, isOwnProfile: isOwnProfile)
                        ProfileTabPicker(selection: $selectedTab, tabs: visibleTabs)
                        tabContent(for: profile)
                            .padding(.top, 12)
                        SimilarProjectsSection(targetProfileID: profile.id)
                            .padding(.top, 20)
                    }
                }
            } else if isLoading {
                ProgressView()
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding()
            }
        }
        .floatingTabBarClearance()
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UUID.self) { ProjectDetailView(projectID: $0) }
        .navigationDestination(item: $chatRoute) { route in
            ChatThreadView(
                conversationID: route.conversationID, otherUserID: route.otherUserID,
                otherSummary: route.otherSummary)
        }
        .task { await load() }
        .task(id: userID) { isGitHubVerified = await GitHubService.isConnected(profileID: userID) }
        .task(id: userID) { await loadTheirStories() }
        .task(id: userID) {
            guard !isOwnProfile else { return }
            isBlocked = await ModerationService.isBlocked(profileID: userID)
            haveIBlocked = await ModerationService.haveIBlocked(profileID: userID)
        }
        .sheet(isPresented: $isPresentingReport) {
            ReportSheet(targetType: .profile, targetID: userID)
        }
        .confirmationDialog(
            "Block this profile?", isPresented: $isPresentingBlockConfirm, titleVisibility: .visible
        ) {
            Button("Block", role: .destructive) { Task { await blockTapped() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won't see each other's content, and you won't be able to follow or message each other.")
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: isBlocked)
    }

    private func blockTapped() async {
        guard await ModerationService.block(profileID: userID) else { return }
        isBlocked = true
        haveIBlocked = true
        AnalyticsService.track("profile_blocked")
    }

    private func unblockTapped() async {
        guard await ModerationService.unblock(profileID: userID) else { return }
        isBlocked = false
        haveIBlocked = false
        AnalyticsService.track("profile_unblocked")
    }

    private func loadTheirStories() async {
        let items: [StoryFeedItem] =
            (try? await SupabaseManager.shared.client
                .from("active_stories_feed")
                .select()
                .eq("author_id", value: userID)
                .order("created_at")
                .execute()
                .value) ?? []
        theirStories = items.map {
            Story(
                id: $0.id, authorID: $0.authorID, mediaURL: $0.mediaURL, mediaType: $0.mediaType,
                createdAt: $0.createdAt, expiresAt: $0.expiresAt)
        }
        theirStoriesHaveUnseen = items.contains { !$0.viewedByMe }
    }

    @ViewBuilder
    private func tabContent(for profile: Profile) -> some View {
        switch selectedTab {
        case .projects: ProjectsTabContent(ownerID: profile.id)
        case .posts: PostsTabContent(ownerID: profile.id)
        case .notes: NotesTabContent(authorID: profile.id)
        case .saved: EmptyView()
        case .achievements: AchievementsTabContent(currentLevel: currentLevel, profile: nil)
        }
    }

    @ViewBuilder
    private func header(for profile: Profile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
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

                Button {
                    guard !theirStories.isEmpty else { return }
                    isPresentingStoryViewer = true
                } label: {
                    StoryRingAvatar(
                        avatarURL: profile.avatarURL, placeholderInitial: profile.displayName,
                        diameter: 84,
                        ringState: theirStories.isEmpty ? .none : (theirStoriesHaveUnseen ? .unseen : .seen))
                }
                .buttonStyle(.plain)
                .disabled(theirStories.isEmpty)
                .accessibilityLabel(theirStories.isEmpty ? "" : "View \(profile.displayName)'s story")
                .fullScreenCover(isPresented: $isPresentingStoryViewer) {
                    StoryViewerView(
                        stories: theirStories, startIndex: 0, authorID: profile.id,
                        authorUsername: profile.username, authorDisplayName: profile.displayName,
                        authorAvatarURL: profile.avatarURL, isOwnStory: false)
                }
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
                            }
                        }
                        Spacer(minLength: 8)
                        ShareLink(item: ShareLinks.profile(username: profile.username)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Share profile")

                        if !isOwnProfile {
                            Menu {
                                Button {
                                    isPresentingReport = true
                                } label: {
                                    Label("Report Profile", systemImage: "flag")
                                }
                                if haveIBlocked {
                                    Button {
                                        Task { await unblockTapped() }
                                    } label: {
                                        Label("Unblock", systemImage: "hand.raised.slash")
                                    }
                                } else {
                                    Button(role: .destructive) {
                                        isPresentingBlockConfirm = true
                                    } label: {
                                        Label("Block", systemImage: "hand.raised.fill")
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .accessibilityLabel("More options")
                        }
                    }
                    .font(.title3)
                    .foregroundStyle(.primary)

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

                if !isOwnProfile && !isBlocked {
                    HStack(spacing: 12) {
                        FollowButton(target: .profile(profile.id))
                        Button {
                            Task { await messageTapped(profile: profile) }
                        } label: {
                            Label("Message", systemImage: "message")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                LevelBadge(profileID: profile.id) { currentLevel = $0.level }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            profile =
                try await SupabaseManager.shared.client
                .from("profiles")
                .select()
                .eq("id", value: userID)
                .single()
                .execute()
                .value
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    /// The DB enforces `user_one_id < user_two_id` so a pair of users maps
    /// to exactly one conversation regardless of who starts it — comparing
    /// `uuidString`s lexicographically matches Postgres's own byte-level
    /// uuid ordering, so this picks the same order the CHECK constraint
    /// expects rather than guessing and risking a rejected insert.
    private func messageTapped(profile: Profile) async {
        guard let currentUserID = SupabaseManager.shared.client.auth.currentSession?.user.id else {
            return
        }
        let (userOne, userTwo) =
            currentUserID.uuidString < profile.id.uuidString
            ? (currentUserID, profile.id) : (profile.id, currentUserID)

        do {
            let conversation: Conversation =
                try await SupabaseManager.shared.client
                .from("conversations")
                .upsert(
                    NewConversation(userOneID: userOne, userTwoID: userTwo),
                    onConflict: "user_one_id,user_two_id"
                )
                .select(
                    """
                    *, \
                    user_one:profiles!conversations_user_one_id_fkey(username,display_name,avatar_url), \
                    user_two:profiles!conversations_user_two_id_fkey(username,display_name,avatar_url)
                    """
                )
                .single()
                .execute()
                .value
            chatRoute = ChatRoute(
                conversationID: conversation.id,
                otherUserID: profile.id,
                otherSummary: UserSummary(
                    username: profile.username, displayName: profile.displayName,
                    avatarURL: profile.avatarURL)
            )
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}

private struct NewConversation: Encodable {
    let userOneID: UUID
    let userTwoID: UUID

    enum CodingKeys: String, CodingKey {
        case userOneID = "user_one_id"
        case userTwoID = "user_two_id"
    }
}

/// "You might also like" — other users' projects sharing a category or
/// tag with this profile's own projects, so a profile visit doesn't dead-
/// end once you've seen what they've built.
private struct SimilarProjectsSection: View {
    let targetProfileID: UUID

    @State private var projects: [DiscoverProject] = []

    var body: some View {
        Group {
            if !projects.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Similar projects")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)

                    LazyVStack(spacing: 12) {
                        ForEach(projects) { project in
                            DiscoverProjectRow(project: project)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        projects =
            (try? await SupabaseManager.shared.client
                .rpc(
                    "similar_projects_to_profile",
                    params: SimilarProjectsParams(targetProfileID: targetProfileID, limitCount: 6)
                )
                .execute()
                .value) ?? []
    }
}

private struct SimilarProjectsParams: Encodable {
    let targetProfileID: UUID
    let limitCount: Int

    enum CodingKeys: String, CodingKey {
        case targetProfileID = "target_profile_id"
        case limitCount = "limit_count"
    }
}
