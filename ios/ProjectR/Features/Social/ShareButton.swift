import SwiftUI

/// One tap = the real system share sheet, immediately — no custom window
/// in front of it. "Send in ProjectR" is embedded as a real activity
/// inside that same native sheet (see `ActivityShareSheet`); only if
/// someone actually picks it does a second, necessary screen (who to send
/// to) appear.
struct ShareButton: View {
    let projectID: UUID
    let projectName: String
    let projectSlug: String

    @State private var isPresentingActivitySheet = false
    @State private var isPresentingFollowerPicker = false

    private var shareURL: URL { ShareLinks.project(slug: projectSlug) }

    var body: some View {
        Button {
            isPresentingActivitySheet = true
        } label: {
            Image(systemName: "paperplane")
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Share")
        .sheet(isPresented: $isPresentingActivitySheet) {
            ActivityShareSheet(items: [shareURL]) {
                // Fires while the native sheet is still mid-dismiss —
                // waiting a beat avoids asking SwiftUI to present a second
                // sheet before the first has actually finished closing.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isPresentingFollowerPicker = true
                }
            }
        }
        .sheet(isPresented: $isPresentingFollowerPicker) {
            SendToFollowerSheet(messageBody: "Check out \(projectName) on ProjectR: \(shareURL.absoluteString)")
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
