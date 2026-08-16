import Supabase
import SwiftUI

struct DiscoverView: View {
    enum Mode: String, CaseIterable {
        case trending = "Trending"
        case following = "Following"
    }

    @State private var mode: Mode = .trending
    @State private var selectedCategory: ProjectCategory?
    @State private var searchText = ""

    @State private var projects: [DiscoverProject] = []
    @State private var feedItems: [FeedItem] = []
    @State private var searchResults: [DiscoverProject] = []
    @State private var searchCreators: [Profile] = []
    @State private var suggestedProfiles: [Profile] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Combined into one string so `.task(id:)` reloads exactly when any of
    /// these actually change, and debounces search keystrokes for free —
    /// SwiftUI cancels the in-flight task when the id changes.
    private var loadKey: String {
        "\(mode.rawValue)|\(selectedCategory?.rawValue ?? "")|\(searchText)"
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            if !isSearching {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 10)

                if mode != .following {
                    categoryChips
                }
            }
            content
        }
        .floatingTabBarClearance()
        // Discover is always this tab's own root (never pushed onto), so
        // there's no back button/title it needs a system nav bar for —
        // hiding it removes the blank bar that used to sit above
        // `.searchable`'s drawer, letting the search field itself be the
        // very first thing on the screen instead.
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: UUID.self) { ProjectDetailView(projectID: $0) }
        .navigationDestination(for: CreatorRoute.self) { CreatorProfileView(userID: $0.userID) }
        .task(id: loadKey) { await load() }
        .task { await loadSuggestedProfiles() }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search projects and creators", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var suggestedProfilesRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested for you")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(suggestedProfiles) { profile in
                        SuggestedProfileCard(profile: profile)
                    }
                }
            }
        }
    }

    private func loadSuggestedProfiles() async {
        guard SupabaseManager.shared.client.auth.currentSession != nil else { return }
        suggestedProfiles =
            (try? await SupabaseManager.shared.client
                .rpc("suggested_profiles", params: ["limit_count": 12])
                .execute()
                .value) ?? []
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                chip(title: "All", isSelected: selectedCategory == nil) { selectedCategory = nil }
                ForEach(ProjectCategory.allCases) { category in
                    chip(
                        title: category.rawValue.capitalized,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = category
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if isSearching {
            searchResultsList
        } else if mode == .following {
            followingList
        } else {
            trendingList
        }
    }

    private var trendingList: some View {
        Group {
            if isLoading && projects.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if projects.isEmpty {
                ContentUnavailableView("No trending projects yet", systemImage: "flame")
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if !suggestedProfiles.isEmpty {
                            suggestedProfilesRow
                        }
                        ForEach(projects) { project in
                            FeedPostCard(project: project)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                }
                .refreshable { await load() }
            }
        }
    }

    private var followingList: some View {
        Group {
            if isLoading && feedItems.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if feedItems.isEmpty {
                ContentUnavailableView(
                    "Nothing yet",
                    systemImage: "person.2",
                    description: Text("Follow some creators or projects to see their updates here.")
                )
            } else {
                List(feedItems) { item in
                    NavigationLink(value: item.projectID) {
                        FollowingFeedRow(item: item)
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }
        }
    }

    private var searchResultsList: some View {
        List {
            if !searchCreators.isEmpty {
                Section("Creators") {
                    ForEach(searchCreators) { profile in
                        NavigationLink(value: CreatorRoute(userID: profile.id)) {
                            HStack(spacing: 6) {
                                Text(profile.displayName)
                                Text("@\(profile.username)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if !searchResults.isEmpty {
                Section("Projects") {
                    ForEach(searchResults) { project in
                        DiscoverProjectRow(project: project)
                    }
                }
            }
            if !isLoading && searchCreators.isEmpty && searchResults.isEmpty {
                Text("No results.").foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
    }

    private func load() async {
        if isSearching {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await runSearch()
            return
        }

        isLoading = true
        defer { isLoading = false }
        do {
            switch mode {
            case .trending:
                var filterQuery = SupabaseManager.shared.client.from("project_feed").select()
                if let selectedCategory {
                    filterQuery = filterQuery.eq("category", value: selectedCategory.rawValue)
                }
                projects =
                    try await filterQuery
                    .order("trending_score", ascending: false)
                    .limit(30)
                    .execute()
                    .value
            case .following:
                feedItems =
                    try await SupabaseManager.shared.client
                    .from("following_feed")
                    .select()
                    .order("created_at", ascending: false)
                    .limit(30)
                    .execute()
                    .value
            }
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func runSearch() async {
        isLoading = true
        defer { isLoading = false }

        // Strip characters that are syntactically meaningful to PostgREST's
        // `or=(...)` filter DSL so a search containing them doesn't corrupt
        // the query — this is a search box, not a place worth hardening
        // further than that.
        let sanitized =
            searchText
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
        guard !sanitized.isEmpty else {
            searchResults = []
            searchCreators = []
            return
        }

        async let projectsTask: [DiscoverProject] =
            SupabaseManager.shared.client
            .from("project_feed")
            .select()
            .textSearch("search_vector", query: sanitized, config: "english", type: .websearch)
            .order("trending_score", ascending: false)
            .limit(30)
            .execute()
            .value
        async let creatorsTask: [Profile] =
            SupabaseManager.shared.client
            .from("profiles")
            .select()
            .or("username.ilike.%\(sanitized)%,display_name.ilike.%\(sanitized)%")
            .limit(10)
            .execute()
            .value

        searchResults = (try? await projectsTask) ?? []
        searchCreators = (try? await creatorsTask) ?? []
    }
}

/// Card content (avatar/name) is its own `NavigationLink` rather than
/// wrapping the whole card — `FollowButton` sits alongside it, not nested
/// inside, so tapping Follow doesn't also trigger navigation.
private struct SuggestedProfileCard: View {
    let profile: Profile

    var body: some View {
        VStack(spacing: 8) {
            NavigationLink(value: CreatorRoute(userID: profile.id)) {
                VStack(spacing: 8) {
                    avatar
                    VStack(spacing: 2) {
                        Text(profile.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("@\(profile.username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            FollowButton(target: .profile(profile.id))
                .controlSize(.small)
        }
        .frame(width: 108)
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = profile.avatarURL.flatMap(URL.init) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
        } else {
            placeholder
                .frame(width: 64, height: 64)
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.2))
            .overlay(
                Text(profile.displayName.prefix(1).uppercased())
                    .font(.headline)
                    .foregroundStyle(Color.accentColor)
            )
    }
}
