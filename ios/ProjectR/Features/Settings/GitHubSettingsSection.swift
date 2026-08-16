import SwiftUI

/// Connecting used to only happen reactively, mid-download-flow on someone
/// else's open-source project. Surfacing it in Settings lets it happen
/// proactively — once connected, `CreateProjectView` can offer "Import
/// from GitHub" to prefill a new project from a real repo instead of
/// typing everything by hand.
struct GitHubSettingsSection: View {
    @State private var isConnected = false
    @State private var username: String?
    @State private var isConnecting = false
    @State private var isDisconnecting = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if isConnected {
                HStack {
                    GitHubMarkIcon()
                        .fill(Color.primary)
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connected")
                        if let username {
                            Text("@\(username)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if isDisconnecting {
                        ProgressView()
                    } else {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Button("Disconnect", role: .destructive) {
                    Task { await disconnect() }
                }
                .disabled(isDisconnecting)
            } else {
                Button {
                    Task { await connect() }
                } label: {
                    HStack {
                        if isConnecting {
                            ProgressView()
                        } else {
                            GitHubMarkIcon()
                                .fill(Color.primary)
                                .frame(width: 18, height: 18)
                        }
                        Text(isConnecting ? "Waiting for GitHub…" : "Connect GitHub")
                    }
                }
                .disabled(isConnecting)
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("GitHub")
        } footer: {
            Text(
                "Connect once to fork open-source projects with one tap, and to import your repos when creating a new project."
            )
        }
        .task { await refresh() }
    }

    private func connect() async {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        if await GitHubService.connectAndWait() {
            await refresh()
        } else {
            errorMessage = "Didn't hear back from GitHub — try again."
        }
    }

    private func refresh() async {
        isConnected = await GitHubService.isConnected()
        username = isConnected ? await GitHubService.myUsername() : nil
    }

    private func disconnect() async {
        isDisconnecting = true
        errorMessage = nil
        defer { isDisconnecting = false }
        do {
            try await GitHubService.disconnect()
            isConnected = false
            username = nil
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}
