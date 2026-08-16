import SwiftUI

/// Instagram-style link row(s) under the bio — compact, tappable, opens
/// externally via `Link` rather than an in-app browser.
struct ProfileLinksSection: View {
    let links: [ProfileLink]

    var body: some View {
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(links, id: \.url) { link in
                    if let url = URL(string: link.url) {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Image(systemName: "link")
                                    .font(.caption)
                                Text(link.label.isEmpty ? displayHost(for: url) : link.label)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    private func displayHost(for url: URL) -> String {
        url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
    }
}
