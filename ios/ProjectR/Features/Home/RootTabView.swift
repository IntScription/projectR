import Supabase
import SwiftUI
import UIKit

struct RootTabView: View {
    let auth: AuthViewModel
    @Binding var profile: Profile

    enum Tab: CaseIterable {
        case home, discover, add, forge, chat, profile

        var icon: String {
            switch self {
            case .home: "house.fill"
            case .discover: "magnifyingglass"
            case .add: "plus"
            case .forge: "hammer.fill"
            case .chat: "bubble.left.and.bubble.right.fill"
            case .profile: "person.fill"
            }
        }

        var label: String {
            switch self {
            case .home: "Home"
            case .discover: "Discover"
            case .add: "Add"
            case .forge: "Forge"
            case .chat: "Chat"
            case .profile: "Profile"
            }
        }
    }

    @State private var selectedTab: Tab = .home
    @State private var visitedTabs: Set<Tab> = [.home]
    @State private var homePath = NavigationPath()
    @State private var discoverPath = NavigationPath()
    @State private var forgePath = NavigationPath()
    @State private var chatPath = NavigationPath()
    @State private var profilePath = NavigationPath()
    @State private var unreadMessageCount = 0

    // Forge needs a connected GitHub account to do anything at all, so
    // the tab itself stays hidden until one exists — a tab that always
    // leads to an empty "Connect GitHub" state is worse than not showing
    // it, and it doubles as the moment worth introducing Forge with
    // `ForgeIntroSheet` rather than a silently-appearing icon.
    @State private var isGitHubConnected = false
    @State private var isPresentingForgeIntro = false

    // Shown once per app version — covers both a brand-new user's first
    // sign-in and an existing user reopening the app after an update,
    // since both land here the same way. An empty stored value (nobody's
    // seen anything yet) and a changed one (an update shipped) both read
    // as "not seen this version," so one comparison covers both cases.
    @AppStorage("lastSeenIntroVersion") private var lastSeenIntroVersion = ""
    @State private var isPresentingAppIntro = false
    private var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private var visibleTabs: [Tab] {
        isGitHubConnected ? Tab.allCases : Tab.allCases.filter { $0 != .forge }
    }

    /// Swiping only changes tabs while the current tab's `NavigationStack`
    /// is at its root — otherwise it'd fight the standard edge-swipe-to-go-
    /// -back gesture on any pushed screen (`ProjectDetailView`,
    /// `CreatorProfileView`, a chat thread). `Add` has no push navigation
    /// at all (only sheets), so it's always effectively "at root."
    private var isAtRootOfCurrentTab: Bool {
        switch selectedTab {
        case .home: homePath.isEmpty
        case .discover: discoverPath.isEmpty
        case .add: true
        case .forge: forgePath.isEmpty
        case .chat: chatPath.isEmpty
        case .profile: profilePath.isEmpty
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                tabContent(.home) {
                    NavigationStack(path: $homePath) { HomeView() }
                }
                tabContent(.discover) {
                    NavigationStack(path: $discoverPath) { DiscoverView() }
                }
                tabContent(.add) {
                    AddView(profile: profile)
                }
                tabContent(.forge) {
                    NavigationStack(path: $forgePath) { ForgeLauncherView(profile: profile) }
                }
                tabContent(.chat) {
                    NavigationStack(path: $chatPath) { ChatListView() }
                }
                tabContent(.profile) {
                    NavigationStack(path: $profilePath) { ProfileView(profile: $profile, auth: auth) }
                }
            }
            .gesture(swipeGesture)

            FloatingTabBar(tabs: visibleTabs, selectedTab: $selectedTab, unreadMessageCount: unreadMessageCount) {
                tab in
                visitedTabs.insert(tab)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $isPresentingForgeIntro) {
            ForgeIntroSheet {
                visitedTabs.insert(.forge)
                withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                    selectedTab = .forge
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(
            isPresented: $isPresentingAppIntro,
            onDismiss: { lastSeenIntroVersion = currentAppVersion }
        ) {
            AppIntroSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task {
            if lastSeenIntroVersion != currentAppVersion {
                isPresentingAppIntro = true
            }
        }
        .task {
            isGitHubConnected = await GitHubService.isConnected()
        }
        .onReceive(NotificationCenter.default.publisher(for: .gitHubDidConnect)) { _ in
            let wasConnected = isGitHubConnected
            isGitHubConnected = true
            if !wasConnected {
                isPresentingForgeIntro = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .gitHubDidDisconnect)) { _ in
            isGitHubConnected = false
            if selectedTab == .forge {
                selectedTab = .home
            }
        }
        .task(id: DeepLinkRouter.shared.pendingDestination) {
            await routePendingDeepLink()
        }
        .task {
            await PushRegistrar.requestAuthorizationAndRegister()
        }
        .task(id: selectedTab) {
            await refreshUnreadMessageCount()
        }
        .task {
            await subscribeToNewMessages()
        }
    }

    /// A decisively horizontal, fairly long drag anywhere in a tab's
    /// content moves to the next/previous tab — Instagram-style
    /// swipe-between-tabs rather than only tapping the bar. Evaluated
    /// entirely in `onEnded` (never `onChanged`) so it doesn't fight each
    /// tab's own scrolling while the drag is in progress.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                guard isAtRootOfCurrentTab else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical) * 1.5, abs(horizontal) > 60 else { return }

                let tabs = visibleTabs
                guard let currentIndex = tabs.firstIndex(of: selectedTab) else { return }
                let newIndex = currentIndex + (horizontal < 0 ? 1 : -1)
                guard tabs.indices.contains(newIndex) else { return }

                let newTab = tabs[newIndex]
                visitedTabs.insert(newTab)
                withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                    selectedTab = newTab
                }
            }
    }

    private func refreshUnreadMessageCount() async {
        unreadMessageCount =
            (try? await Engagement.count(table: "unread_messages", filters: [:])) ?? 0
    }

    /// Unfiltered — every new message anywhere triggers a re-count rather
    /// than trying to express "only conversations I'm in" as a
    /// `postgres_changes` filter (that needs a subquery, which the filter
    /// DSL can't express). The re-count itself is still correctly scoped
    /// by `unread_messages`' own RLS, so this only ever costs an extra
    /// cheap query, never a wrong badge number.
    private func subscribeToNewMessages() async {
        let channel = SupabaseManager.shared.client.channel("app:unread-messages")
        let changes = channel.postgresChange(InsertAction.self, schema: "public", table: "messages")
        await channel.subscribe()

        for await _ in changes {
            await refreshUnreadMessageCount()
        }
    }

    /// Lazy on first visit, then kept mounted (just hidden) so switching
    /// tabs doesn't lose scroll position, in-progress search text, etc. —
    /// the same persistence a system `TabView` gives you for free.
    @ViewBuilder
    private func tabContent(_ tab: Tab, @ViewBuilder content: () -> some View) -> some View {
        if visitedTabs.contains(tab) {
            content()
                .opacity(selectedTab == tab ? 1 : 0)
                .allowsHitTesting(selectedTab == tab)
        }
    }

    /// Deep links only carry a slug/username, not the row id our
    /// navigation values are keyed on, so this resolves one before pushing.
    private func routePendingDeepLink() async {
        guard let destination = DeepLinkRouter.shared.pendingDestination else { return }
        DeepLinkRouter.shared.pendingDestination = nil
        visitedTabs.insert(.discover)
        selectedTab = .discover

        do {
            switch destination {
            case .project(let slug):
                let row: IDRow =
                    try await SupabaseManager.shared.client
                    .from("projects")
                    .select("id")
                    .eq("slug", value: slug)
                    .single()
                    .execute()
                    .value
                discoverPath.append(row.id)
            case .profile(let username):
                let row: IDRow =
                    try await SupabaseManager.shared.client
                    .from("profiles")
                    .select("id")
                    .eq("username", value: username)
                    .single()
                    .execute()
                    .value
                discoverPath.append(CreatorRoute(userID: row.id))
            }
        } catch {
            // Unresolvable slug/username — nothing to navigate to.
        }
    }
}

private struct IDRow: Decodable {
    let id: UUID
}

/// Floating, blurred, rounded bar with an animated highlight that slides
/// behind the selected tab — replaces the system tab bar chrome entirely.
/// Each tab gets a fixed-width slot rather than splitting the bar evenly,
/// and the bar itself is capped to exactly `visibleTabCount` slots wide —
/// so it always reads as a deliberate 4-tab bar, with the rest a
/// horizontal scroll away, rather than stretching (and squeezing every
/// icon) to fill whatever the device's screen width happens to be.
private struct FloatingTabBar: View {
    var tabs: [RootTabView.Tab]
    @Binding var selectedTab: RootTabView.Tab
    var unreadMessageCount: Int
    var onSelect: (RootTabView.Tab) -> Void
    @Namespace private var indicatorNamespace

    private let tabWidth: CGFloat = 60
    private let tabSpacing: CGFloat = 4
    private let outerPadding: CGFloat = 6
    private let visibleTabCount: CGFloat = 4

    private var barWidth: CGFloat {
        visibleTabCount * tabWidth + (visibleTabCount - 1) * tabSpacing + 2 * outerPadding
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: tabSpacing) {
                ForEach(tabs, id: \.self) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(outerPadding)
        }
        .frame(width: barWidth)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
    }

    private func tabButton(for tab: RootTabView.Tab) -> some View {
        Button {
            onSelect(tab)
            withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: tab == .add ? 20 : 18, weight: .semibold))
                    .overlay(alignment: .topTrailing) {
                        if tab == .chat && unreadMessageCount > 0 {
                            Circle()
                                .fill(.red)
                                .frame(width: 7, height: 7)
                                .offset(x: 6, y: -4)
                        }
                    }
                Text(tab.label)
                    .font(.system(size: 10, weight: .medium))
            }
            // `Color.secondary` renders invisible here specifically —
            // hosted inside a horizontally scrolling `ScrollView` over an
            // `.ultraThinMaterial` background, it never resolves to a
            // visible tint (confirmed by swapping in plain colors, which
            // render fine). The UIKit-bridged equivalent doesn't have
            // this problem and is just as dark-mode-adaptive.
            .foregroundStyle(selectedTab == tab ? Color.accentColor : Color(uiColor: .secondaryLabel))
            .frame(width: 60)
            .padding(.vertical, 10)
            .background {
                if selectedTab == tab {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                        .matchedGeometryEffect(id: "tab-indicator", in: indicatorNamespace)
                }
            }
        }
        .buttonStyle(.plain)
        // The Image and Text are otherwise exposed as two separate
        // elements — combine so VoiceOver announces one clean
        // "Chat, unread messages, tab, selected"-style label
        // instead of swiping through icon and text individually.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            tab == .chat && unreadMessageCount > 0
                ? "\(tab.label), unread messages" : tab.label
        )
        .accessibilityAddTraits(selectedTab == tab ? [.isButton, .isSelected] : .isButton)
    }
}
