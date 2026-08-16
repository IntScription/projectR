import SwiftUI

struct DiscoverProjectRow: View {
    let project: DiscoverProject

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Only this part navigates — the like button is its own tap
            // target outside the link, same reasoning as FeedPostCard.
            NavigationLink(value: project.id) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name).font(.headline)
                    if let description = project.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 8) {
                        Text("@\(project.ownerUsername)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(project.status.rawValue.capitalized)
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            HStack(spacing: 14) {
                LikeButton(
                    target: .project(project.id),
                    preloaded: (isLiked: project.isLikedByMe, count: project.likeCount)
                )
                ShareButton(projectID: project.id, projectName: project.name, projectSlug: project.slug)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
