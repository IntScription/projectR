import SwiftUI

/// A social-feed-style post card — shared by Home and Discover's trending
/// list so both read as the same feed rather than one being a "real" feed
/// and the other a plain list. ProjectR has no separate "post" object at
/// the top level (everything ties back to a project by design), so a
/// project card doubles as the feed's post unit: creator header, cover
/// media, engagement row, caption.
struct FeedPostCard: View {
    let project: DiscoverProject

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Only the header+media area navigates to the project — the
            // engagement row below is its own tap target, outside this
            // link entirely, so liking/commenting never fights a parent
            // NavigationLink for the tap (a real bug this replaced: the
            // whole card used to be one giant NavigationLink, so tapping
            // a "heart" that was really just static text always navigated
            // away instead of liking anything).
            NavigationLink(value: project.id) {
                ZStack(alignment: .topTrailing) {
                    media
                        .frame(height: 260)
                        .clipped()
                    categoryBadge
                }
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topLeading) {
                avatarButton
                    .padding(10)
            }
            engagementRow
            caption
        }
        .background(Color(.secondarySystemGroupedBackground))
        // `.background(in:)` alone doesn't clip the content to that
        // shape — without this, the media at the top (which has square
        // corners of its own) would just overhang the rounded background
        // underneath it instead of actually being rounded itself.
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Its own tap target, separate from the project link underneath —
    /// tapping the creator's face goes straight to their profile, the
    /// same "avatar = person, everything else = the thing they made"
    /// split Instagram uses. Floats directly on the media rather than
    /// taking its own row above it, so the banner gets the screen space
    /// that row used to claim; a thin background-colored ring (not a
    /// filled material pill, since there's no text needing a legibility
    /// backdrop anymore) keeps it readable against busy media.
    private var avatarButton: some View {
        NavigationLink(value: CreatorRoute(userID: project.ownerID)) {
            AsyncImage(url: project.ownerAvatarURL.flatMap(URL.init)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(Color.accentColor.opacity(0.3)).overlay(
                    Text(project.ownerDisplayName.prefix(1).uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                )
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(.systemBackground).opacity(0.9), lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(project.ownerDisplayName)'s profile")
    }

    private var categoryBadge: some View {
        Text(project.category.rawValue.capitalized)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(Color.accentColor)
            .padding(10)
    }

    @ViewBuilder
    private var media: some View {
        if let videoURL = project.coverVideoURL.flatMap(URL.init) {
            FeedVideoPlayer(url: videoURL)
        } else if let url = project.coverImageURL.flatMap(URL.init) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                mediaPlaceholder
            }
        } else {
            mediaPlaceholder
        }
    }

    private var mediaPlaceholder: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.1)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay {
            Text(project.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private var engagementRow: some View {
        HStack(spacing: 18) {
            LikeButton(
                target: .project(project.id),
                preloaded: (isLiked: project.isLikedByMe, count: project.likeCount)
            )
            CommentButton(target: .project(project.id), preloadedCount: project.commentCount)
            ShareButton(projectID: project.id, projectName: project.name, projectSlug: project.slug)
            Spacer()
            SaveButton(projectID: project.id)
            Text(project.status.rawValue.capitalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(project.name)
                .font(.headline)
            if let description = project.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
