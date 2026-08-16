import SwiftUI

struct FollowingFeedRow: View {
    let item: FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(item.ownerDisplayName).font(.subheadline.bold())
                Text(headline).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(item.text).lineLimit(3)
            Text(item.createdAt, format: .dateTime.month(.abbreviated).day())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var headline: String {
        switch item.itemType {
        case .update: "posted an update on \(item.projectName)"
        case .newProject: "started a new project: \(item.projectName)"
        }
    }
}
