import SwiftUI

struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if !notification.isRead {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                text
                Text(notification.createdAt, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var text: Text {
        let name = Text(notification.actor.displayName).fontWeight(.semibold)
        switch notification.type {
        case .follow:
            return name + Text(" started following you")
        case .like:
            return name + Text(notification.updateID != nil ? " liked your update" : " liked your project")
        case .comment:
            return name
                + Text(
                    notification.updateID != nil
                        ? " commented on your update" : " commented on your project")
        case .update:
            return name + Text(" posted an update")
        case .newProject:
            return name + Text(" shipped a new project")
        case .note:
            return name + Text(" posted a note")
        }
    }
}
