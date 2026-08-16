import SwiftUI

/// The real system share sheet (`UIActivityViewController`), not SwiftUI's
/// `ShareLink` — `ShareLink` can't carry a custom activity, and putting
/// "send to a follower" behind an extra custom screen ahead of the native
/// sheet meant two windows to get anywhere. Here the native sheet with
/// every installed app (Messages, WhatsApp, Instagram, ...) is the first
/// and only thing that opens; "Send in ProjectR" is just one more icon
/// inside it, wired via `onSendInApp` to whatever the caller wants to show
/// next (see `ShareButton`) only if someone actually taps it.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onSendInApp: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let sendInAppActivity = SendInAppActivity(onPerform: onSendInApp)
        return UIActivityViewController(activityItems: items, applicationActivities: [sendInAppActivity])
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private final class SendInAppActivity: UIActivity {
    private let onPerform: () -> Void

    init(onPerform: @escaping () -> Void) {
        self.onPerform = onPerform
        super.init()
    }

    override var activityTitle: String? { "Send in ProjectR" }
    override var activityImage: UIImage? {
        UIImage(systemName: "paperplane.fill")
    }
    override class var activityCategory: UIActivity.Category { .share }
    override func canPerform(withActivityItems items: [Any]) -> Bool { true }

    override func perform() {
        onPerform()
        activityDidFinish(true)
    }
}
