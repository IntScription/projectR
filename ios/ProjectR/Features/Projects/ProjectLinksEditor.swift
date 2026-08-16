import SwiftUI

/// Free-form label+url rows — anything besides GitHub (website, App
/// Store, Play Store, demo video, docs...) instead of one fixed "website"
/// field. Mirrors how `profile.links` already works.
struct ProjectLinksEditor: View {
    @Binding var links: [ProfileLink]

    private static let suggestions = ["Website", "App Store", "Play Store", "Demo", "Docs"]

    var body: some View {
        ForEach($links, id: \.url) { $link in
            HStack(spacing: 10) {
                Menu {
                    ForEach(Self.suggestions, id: \.self) { suggestion in
                        Button(suggestion) { link.label = suggestion }
                    }
                } label: {
                    Text(link.label.isEmpty ? "Label" : link.label)
                        .font(.subheadline)
                        .foregroundStyle(link.label.isEmpty ? .secondary : .primary)
                        .frame(width: 92, alignment: .leading)
                }
                TextField("https://…", text: $link.url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    links.removeAll { $0.url == link.url && $0.label == link.label }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("Remove link")
            }
        }
        Button {
            links.append(ProfileLink(label: "Website", url: ""))
        } label: {
            Label("Add link", systemImage: "plus.circle")
        }
    }
}
