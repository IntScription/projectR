import SwiftUI

/// Wraps `ForgeView` behind `AppLockManager.forge` — every place a
/// `ForgeRoute` resolves (the Forge tab's project list, and a project's
/// own toolbar hammer button) renders this instead of `ForgeView`
/// directly, so there's exactly one gate regardless of entry path.
/// Locked by default each cold launch, and re-locks whenever the app
/// backgrounds — Face ID first, falling back to the device passcode
/// automatically (`AppLockManager` already uses `.deviceOwnerAuthentication`,
/// not the biometrics-only policy).
struct ForgeLockGateView: View {
    let project: Project
    var onProjectUpdated: ((Project) -> Void)?

    private let lock = AppLockManager.forge
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if lock.isLocked {
                lockPrompt
            } else {
                ForgeView(project: project, onProjectUpdated: onProjectUpdated)
            }
        }
        .task {
            if lock.isLocked {
                await lock.authenticate(reason: "Unlock Forge")
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background { lock.lock() }
        }
    }

    private var lockPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 6) {
                Text("Forge is locked")
                    .font(.title3.weight(.semibold))
                Text("Forge can browse, edit, and commit real code — unlock it to continue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                Task { await lock.authenticate(reason: "Unlock Forge") }
            } label: {
                Label(lock.isAuthenticating ? "Unlocking…" : "Unlock Forge", systemImage: "faceid")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(lock.isAuthenticating)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationTitle("Forge")
        .navigationBarTitleDisplayMode(.inline)
    }
}
