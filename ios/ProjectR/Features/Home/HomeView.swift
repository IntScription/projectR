import SwiftUI

/// "Open the app and see something you wouldn't have gone looking for" —
/// a shuffled pool of recent projects, distinct from Discover's
/// intentional search/trending/following. Reshuffles on pull-to-refresh.
/// No `.navigationTitle` — the tab bar already says "Home".
struct HomeView: View {
    @State private var projects: [DiscoverProject] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            StoriesRailView()
            Group {
                if isLoading && projects.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if projects.isEmpty {
                    ContentUnavailableView("Nothing here yet", systemImage: "shuffle")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
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
        .floatingTabBarClearance()
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: UUID.self) { ProjectDetailView(projectID: $0) }
        .navigationDestination(for: CreatorRoute.self) { CreatorProfileView(userID: $0.userID) }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let pool: [DiscoverProject] =
                try await SupabaseManager.shared.client
                .from("project_feed")
                .select()
                .order("created_at", ascending: false)
                .limit(60)
                .execute()
                .value
            projects = pool.shuffled()
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}
