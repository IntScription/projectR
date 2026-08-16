import AuthenticationServices
import GoogleSignInSwift
import SwiftUI

struct SignInView: View {
    @Bindable var auth: AuthViewModel

    @State private var email = ""
    @State private var password = ""
    @State private var mode: Mode = .signIn
    @FocusState private var focusedField: Field?
    @Environment(\.colorScheme) private var colorScheme

    // Entrance choreography: header rotates/fades in, the headline types
    // itself out, then everything below appears once typing finishes — one
    // orchestrated sequence rather than several separate effects competing
    // for attention.
    @State private var headerAppeared = false
    @State private var typedHeadline = ""
    @State private var isCursorVisible = true
    @State private var restAppeared = false

    @State private var isPresentingForgotPassword = false

    private static let headline = "Project your work."

    private enum Mode: String, CaseIterable {
        case signIn = "Sign in"
        case signUp = "Sign up"
    }

    private enum Field {
        case email, password
    }

    var body: some View {
        ZStack {
            background
            CodeParticlesBackground()

            // Wrapped in a `ScrollViewReader` so focusing either field
            // scrolls the form up above the keyboard — a plain
            // `ScrollView` only guarantees the *focused text field*
            // stays visible, not the submit button sitting below it, so
            // without this the button ends up partly hidden once the
            // keyboard is up.
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 32) {
                        header
                        if restAppeared {
                            oauthButtons
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            divider
                                .transition(.opacity)
                            emailForm
                                .id(Field.password)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(24)
                    .padding(.top, 32)
                    .frame(maxWidth: 440)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedField) { _, newValue in
                    guard newValue != nil else { return }
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(Field.password, anchor: .bottom)
                    }
                }
            }
        }
        .task { await runEntrance() }
        .sheet(isPresented: $isPresentingForgotPassword) {
            ForgotPasswordSheet(auth: auth, prefilledEmail: email)
        }
    }

    private var background: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let drift = sin(t * 0.12) * 0.18

            LinearGradient(
                stops: [
                    .init(color: Color.accentColor.opacity(0.28), location: 0),
                    .init(color: Color.accentColor.opacity(0.08), location: 0.45 + drift),
                    .init(color: Color(.systemBackground), location: 0.85),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 14) {
            logo

            Text("PROJECTR")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.semibold)
                .tracking(4)
                .foregroundStyle(Color.accentColor)

            HStack(spacing: 2) {
                Text(typedHeadline)
                    .font(.system(size: 34, weight: .bold, design: .serif))
                if typedHeadline.count < Self.headline.count {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 3, height: 30)
                        .opacity(isCursorVisible ? 1 : 0)
                }
            }
            .multilineTextAlignment(.center)
            .frame(minHeight: 44)

            if restAppeared {
                Text("Where builders show what they're building.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.bottom, 8)
        .rotation3DEffect(
            .degrees(headerAppeared ? 0 : -16),
            axis: (x: 1, y: 0, z: 0),
            anchor: .bottom,
            perspective: 0.6
        )
        .opacity(headerAppeared ? 1 : 0)
        .offset(y: headerAppeared ? 0 : 16)
    }

    private var logo: some View {
        Image("LaunchLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color.accentColor.opacity(0.35), radius: 16, y: 6)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.5), lineWidth: 1)
            )
    }

    private var oauthButtons: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn) { request in
                auth.prepareAppleSignInRequest(request)
            } onCompletion: { result in
                handleAppleCompletion(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

            if auth.isGoogleSignInConfigured {
                GoogleSignInButton(
                    scheme: colorScheme == .dark ? .dark : .light,
                    style: .wide
                ) {
                    Task { await auth.signInWithGoogle() }
                }
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            }
        }
    }

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(.separator).frame(height: 1)
            Text("or")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
            Rectangle().fill(.separator).frame(height: 1)
        }
    }

    private var emailForm: some View {
        VStack(spacing: 20) {
            modeSwitch

            VStack(spacing: 12) {
                fieldContainer(icon: "envelope") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                }

                fieldContainer(icon: "lock") {
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                }
            }

            if mode == .signIn {
                Button("Forgot password?") {
                    isPresentingForgotPassword = true
                }
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if let errorMessage = auth.errorMessage {
                errorBanner(errorMessage)
            }

            Button {
                Task { await submit() }
            } label: {
                Group {
                    if auth.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text(mode.rawValue).fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(email.isEmpty || password.isEmpty || auth.isLoading)
        }
    }

    private var modeSwitch: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases, id: \.self) { candidate in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { mode = candidate }
                } label: {
                    Text(candidate.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .foregroundStyle(mode == candidate ? Color.primary : Color.secondary)
                        .background {
                            if mode == candidate {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.background)
                                    .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func fieldContainer(icon: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            content()
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func submit() async {
        switch mode {
        case .signIn: await auth.signIn(email: email, password: password)
        case .signUp: await auth.signUp(email: email, password: password)
        }
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                Task { await auth.signInWithApple(credential: credential) }
            }
        case .failure(let error):
            auth.errorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func runEntrance() async {
        withAnimation(.spring(duration: 0.6)) {
            headerAppeared = true
        }
        try? await Task.sleep(for: .milliseconds(300))

        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            isCursorVisible.toggle()
        }

        for index in Self.headline.indices {
            typedHeadline = String(Self.headline[...index])
            try? await Task.sleep(for: .milliseconds(38))
        }

        try? await Task.sleep(for: .milliseconds(150))
        withAnimation(.easeOut(duration: 0.45)) {
            restAppeared = true
        }
    }
}

private struct ForgotPasswordSheet: View {
    let auth: AuthViewModel
    @State var prefilledEmail: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $prefilledEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("We'll send a password reset link to this address.")
                }

                if auth.passwordResetSent {
                    Label("Check your email for a reset link.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if let errorMessage = auth.errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if auth.isLoading {
                        ProgressView()
                    } else {
                        Button("Send") {
                            Task { await auth.sendPasswordReset(email: prefilledEmail) }
                        }
                        .disabled(prefilledEmail.isEmpty)
                    }
                }
            }
        }
    }
}
