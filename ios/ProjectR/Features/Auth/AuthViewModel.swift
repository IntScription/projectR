import AuthenticationServices
import CryptoKit
import Foundation
import GoogleSignIn
import Observation
import Supabase
import UIKit

@MainActor
@Observable
final class AuthViewModel {
    private(set) var session: Session?
    var isLoading = false
    var errorMessage: String?

    private let client = SupabaseManager.shared.client

    /// True once a Google OAuth client ID has been supplied in
    /// Config.local.xcconfig — the button is hidden otherwise rather than
    /// shown in a state that can only fail.
    let isGoogleSignInConfigured: Bool

    init() {
        session = client.auth.currentSession

        let googleClientID = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String
        if let googleClientID, !googleClientID.isEmpty {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: googleClientID)
            isGoogleSignInConfigured = true
        } else {
            isGoogleSignInConfigured = false
        }

        Task { [weak self] in
            guard let self else { return }
            for await (_, session) in client.auth.authStateChanges {
                self.session = session
                if let session {
                    await GitHubService.captureToken(from: session)
                }
            }
        }
    }

    func signUp(email: String, password: String) async {
        await run {
            try await self.client.auth.signUp(email: email, password: password)
        }
    }

    func signIn(email: String, password: String) async {
        await run {
            try await self.client.auth.signIn(email: email, password: password)
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    var passwordResetSent = false

    func sendPasswordReset(email: String) async {
        passwordResetSent = false
        await run {
            try await self.client.auth.resetPasswordForEmail(email)
        }
        if errorMessage == nil {
            passwordResetSent = true
        }
    }

    private var currentAppleNonce: String?

    /// Call from the `SignInWithAppleButton` request closure — generates and
    /// remembers a nonce, and attaches its hash to the authorization
    /// request, so the round trip can be verified end to end and GoTrue
    /// doesn't need `skip_nonce_check` to accept native Apple sign-ins.
    func prepareAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentAppleNonce = nonce
        request.requestedScopes = [.email, .fullName]
        request.nonce = Self.sha256(nonce)
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async {
        await run {
            guard let nonce = self.currentAppleNonce else {
                throw AuthError.missingIdentityToken
            }
            guard
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                throw AuthError.missingIdentityToken
            }
            try await self.client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
            )
        }
    }

    private static func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            guard status == errSecSuccess else { continue }
            if random < charset.count {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Requires GOOGLE_CLIENT_ID / GOOGLE_REVERSED_CLIENT_ID in
    /// Config.local.xcconfig — see Config.local.xcconfig.example.
    func signInWithGoogle() async {
        await run {
            guard let presenter = await Self.topViewController() else {
                throw AuthError.noPresentingViewController
            }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthError.missingIdentityToken
            }
            try await self.client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .google, idToken: idToken)
            )
        }
    }

    private func run(_ action: @escaping () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await action()
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }

    private enum AuthError: LocalizedError {
        case missingIdentityToken
        case noPresentingViewController

        var errorDescription: String? {
            switch self {
            case .missingIdentityToken:
                "Sign-in didn't return an identity token."
            case .noPresentingViewController:
                "No view to present the sign-in flow from."
            }
        }
    }
}
