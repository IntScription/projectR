import SwiftUI

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Placeholder text — not yet reviewed by a lawyer. Replace before shipping to real users.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

                LegalSection(title: "What ProjectR is") {
                    Text(
                        "ProjectR is a place to showcase and share what you're building. Every piece of content — updates, comments, media — belongs to a project. There's no general-purpose posting unrelated to something you're building."
                    )
                }

                LegalSection(title: "Acceptable use") {
                    Text(
                        "Post your own work. Don't post content that infringes someone else's intellectual property, harasses or threatens others, is spam, or impersonates someone. We may remove content or suspend accounts that violate this, whether we find it ourselves or another user reports it to us."
                    )
                }

                LegalSection(title: "Blocking and reporting") {
                    Text(
                        "You can block another account at any time — once blocked, neither of you can follow or message the other, and you stop seeing each other's projects and updates. You can report a profile, project, comment, or update that violates these terms; we review reports and may remove content, warn, or suspend the account involved. Submitting a report you know to be false is itself a violation of these terms."
                    )
                }

                LegalSection(title: "Your content") {
                    Text(
                        "You own what you post. By posting it, you grant ProjectR a license to display it within the app and on the public project/profile pages you choose to share — nothing more."
                    )
                }

                LegalSection(title: "Account termination") {
                    Text(
                        "You can delete your account at any time from Settings. We may suspend or terminate accounts that violate these terms."
                    )
                }

                LegalSection(title: "No warranty") {
                    Text(
                        "ProjectR is provided as-is, without warranties of any kind. We don't guarantee the service will be uninterrupted or error-free."
                    )
                }

                LegalSection(title: "Limitation of liability") {
                    Text(
                        "To the extent permitted by law, ProjectR isn't liable for indirect or consequential damages arising from your use of the app."
                    )
                }

                LegalSection(title: "Governing law") {
                    Text("These terms are governed by the laws of [jurisdiction placeholder].")
                }

                LegalSection(title: "Changes") {
                    Text("We may update these terms as the product evolves. Material changes will be reflected here.")
                }

                Text("Last updated: August 2026")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }
}
