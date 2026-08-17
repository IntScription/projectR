import SwiftUI

/// Nowhere in the app previously showed a version/build number — useful
/// the moment this is ever in TestFlight and someone's asking "which
/// version are you on."
struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    if let icon = UIImage(named: "AppIcon") {
                        Image(uiImage: icon)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Text("ProjectR").font(.headline)
                    Text("Version \(version) (\(build))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section {
                Link(destination: URL(string: "mailto:22kartiksanil@gmail.com")!) {
                    Label("Contact support", systemImage: "envelope")
                }
                NavigationLink("Privacy Policy") { PrivacyPolicyView() }
                NavigationLink("Terms of Service") { TermsOfServiceView() }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
