import SwiftUI

/// Rendered in place of `LinkifiedText` when a chat message carries Forge
/// metadata — tapping deep-links straight into the relevant Forge screen
/// instead of leaving the recipient to parse a plain-text link.
struct ForgeShareCard: View {
    let metadata: ForgeShareMetadata

    var body: some View {
        NavigationLink(
            value: ForgeDestination.commitDetail(
                githubURL: metadata.githubURL, sha: metadata.sha, projectID: metadata.projectID)
        ) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(metadata.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(metadata.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
