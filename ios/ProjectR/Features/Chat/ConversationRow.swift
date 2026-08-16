import SwiftUI

struct ConversationRow: View {
    let summary: UserSummary
    let lastMessageAt: Date?

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: summary.avatarURL.flatMap(URL.init)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Circle().fill(.secondary.opacity(0.2))
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.displayName).font(.subheadline.bold())
                Text("@\(summary.username)").font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if let lastMessageAt {
                Text(lastMessageAt, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
