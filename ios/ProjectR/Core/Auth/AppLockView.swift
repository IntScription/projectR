import SwiftUI

/// Full-screen cover shown over `RootTabView` when "Require Face ID" is on
/// and the app just returned to the foreground. Deliberately reuses the
/// auth page's visual language (gradient, code particles, rounded app
/// mark) so it reads as part of the same app, not a bolted-on system sheet.
struct AppLockView: View {
    let appLock: AppLockManager

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.22), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            CodeParticlesBackground()

            VStack(spacing: 20) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 16, y: 6)

                VStack(spacing: 6) {
                    Text("ProjectR is locked")
                        .font(.title3.weight(.semibold))
                    Text("Use Face ID to continue.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await appLock.authenticate() }
                } label: {
                    Label(
                        appLock.isAuthenticating ? "Unlocking…" : "Unlock", systemImage: "faceid"
                    )
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(appLock.isAuthenticating)
                .padding(.horizontal, 40)
                .padding(.top, 12)
            }
        }
        .task {
            await appLock.authenticate()
        }
    }
}
