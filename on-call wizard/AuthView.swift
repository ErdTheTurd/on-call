import SwiftUI
import AuthenticationServices
import CryptoKit

// MARK: - Auth Screen (Sign In / Sign Up)

struct AuthView: View {
    @ObservedObject var auth: AuthService
    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var selectedRole: UserRole = .doctor
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var pendingVerificationEmail: String? = nil
    @State private var otpCode = ""
    @State private var noticeMessage: String? = nil
    @State private var showDevRolePicker = false
    @State private var appleNonce: String?
    @State private var mfaChallenge = false
    @State private var mfaEnroll: SupabaseAuthService.TotpEnrollment? = nil
    @State private var mfaCode = ""
    @Namespace private var ns

    enum AuthMode { case signIn, signUp }

    var body: some View {
        ZStack {
            Color(hex: "0A0F1E").ignoresSafeArea()
            MeshBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(Color(hex: "4F8EF7"))
                            Text("MD Shift")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        Text("Smarter shift scheduling")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .tracking(0.5)
                    }
                    .padding(.top, 64)
                    .padding(.bottom, 48)

                    if mfaChallenge {
                        mfaChallengeCard
                    } else if let enroll = mfaEnroll {
                        mfaEnrollCard(enroll)
                    } else if pendingVerificationEmail != nil {
                        otpCard
                    } else {
                        mainAuthCard
                    }

                    Text("By continuing you agree to our Terms of Service and Privacy Policy.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.2))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 24)
                        .padding(.bottom, 48)
                }
            }
        }
        .withContactSupport()
        .sheet(isPresented: $showDevRolePicker) {
            DevRolePickerView(auth: auth)
        }
    }

    private var mfaChallengeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Authenticator code")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text("Open Google Authenticator (or any TOTP app) and enter the 6-digit code for MD Shift.")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.55))
            codeField(placeholder: "6-digit code", text: $mfaCode) {
                if mfaCode.filter(\.isNumber).count == 6 { submitMfaChallenge() }
            }
            if let err = errorMessage {
                Text(err).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: "F87171"))
            }
            Button { submitMfaChallenge() } label: { authPrimaryLabel("Verify") }
                .buttonStyle(.plain)
                .disabled(isLoading || mfaCode.filter(\.isNumber).count != 6)
            Button {
                mfaChallenge = false
                mfaCode = ""
                try? SupabaseAuthService.shared.signOut()
            } label: {
                Text("Back to sign in").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.white.opacity(0.55)).frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 20)
    }

    private func mfaEnrollCard(_ enroll: SupabaseAuthService.TotpEnrollment) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up authenticator")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text("Add MD Shift in Google Authenticator using this secret, then enter the 6-digit code.")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.55))
            if !enroll.secret.isEmpty {
                Text(enroll.secret)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(hex: "4F8EF7"))
                    .textSelection(.enabled)
            }
            codeField(placeholder: "6-digit code", text: $mfaCode) {
                if mfaCode.filter(\.isNumber).count == 6 { confirmMfaEnroll() }
            }
            if let err = errorMessage {
                Text(err).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: "F87171"))
            }
            Button { confirmMfaEnroll() } label: { authPrimaryLabel("Confirm and continue") }
                .buttonStyle(.plain)
                .disabled(isLoading || mfaCode.filter(\.isNumber).count != 6)
            Button { skipMfaEnroll() } label: {
                Text("Skip for now").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: "4F8EF7")).frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 20)
    }

    private func codeField(placeholder: String, text: Binding<String>, onComplete: @escaping () -> Void) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .multilineTextAlignment(.center)
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .onChange(of: text.wrappedValue) { _, newValue in
                let filtered = newValue.filter(\.isNumber)
                if filtered.count > 6 { text.wrappedValue = String(filtered.prefix(6)) }
                else if filtered != newValue { text.wrappedValue = filtered }
                if text.wrappedValue.count == 6 { onComplete() }
            }
    }

    private func submitMfaChallenge() {
        let code = mfaCode.filter(\.isNumber)
        guard code.count == 6 else { errorMessage = "Enter the 6-digit authenticator code."; return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await SupabaseAuthService.shared.challengeAndVerifyFirstTotp(code: code)
                let role = try await SupabaseAuthService.shared.fetchRoleAfterMfa()
                let mail = email.isEmpty ? (pendingVerificationEmail ?? "user") : normalizeEmail(email)
                await MainActor.run {
                    isLoading = false
                    mfaChallenge = false
                    finishAuth(userID: SupabaseAuthService.shared.currentUserID ?? UUID(), email: mail, role: role)
                }
            } catch {
                await MainActor.run { isLoading = false; errorMessage = error.localizedDescription }
            }
        }
    }

    private func confirmMfaEnroll() {
        guard let enroll = mfaEnroll else { return }
        let code = mfaCode.filter(\.isNumber)
        guard code.count == 6 else { errorMessage = "Enter the 6-digit authenticator code."; return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await SupabaseAuthService.shared.verifyTotp(factorId: enroll.factorId, code: code)
                await MainActor.run {
                    isLoading = false
                    mfaEnroll = nil
                    mfaCode = ""
                    let mail = pendingVerificationEmail ?? normalizeEmail(email)
                    finishAuth(userID: SupabaseAuthService.shared.currentUserID ?? UUID(), email: mail, role: selectedRole)
                }
            } catch {
                await MainActor.run { isLoading = false; errorMessage = error.localizedDescription }
            }
        }
    }

    private func skipMfaEnroll() {
        mfaEnroll = nil
        mfaCode = ""
        let mail = pendingVerificationEmail ?? normalizeEmail(email)
        if let id = SupabaseAuthService.shared.currentUserID {
            finishAuth(userID: id, email: mail, role: selectedRole)
        }
    }

    private func maybePromptMfaEnroll(thenFinish userID: UUID, email: String, role: UserRole, suggest: Bool) {
        guard suggest else {
            finishAuth(userID: userID, email: email, role: role)
            return
        }
        Task {
            do {
                let enroll = try await SupabaseAuthService.shared.enrollTotp()
                await MainActor.run {
                    selectedRole = role
                    pendingVerificationEmail = email
                    mfaEnroll = enroll
                    mfaCode = ""
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    finishAuth(userID: userID, email: email, role: role)
                }
            }
        }
    }

    private var otpCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter verification code")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text("We sent a 6-digit code to \(pendingVerificationEmail ?? ""). Enter it here — no link to click.")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            TextField("", text: $otpCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .onChange(of: otpCode) { _, newValue in
                    let filtered = newValue.filter(\.isNumber)
                    if filtered.count > 6 {
                        otpCode = String(filtered.prefix(6))
                    } else if filtered != newValue {
                        otpCode = filtered
                    }
                    if otpCode.count == 6 { submitOTP() }
                }

            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "F87171"))
            }
            if let notice = noticeMessage {
                Text(notice)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "34D399"))
            }

            Button { submitOTP() } label: {
                authPrimaryLabel("Verify and continue")
            }
            .buttonStyle(.plain)
            .disabled(isLoading || otpCode.count != 6)

            Button { resendVerification() } label: {
                Text("Resend code")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "4F8EF7"))
                    .frame(maxWidth: .infinity)
            }
            .disabled(isLoading)

            Button {
                pendingVerificationEmail = nil
                otpCode = ""
                errorMessage = nil
                noticeMessage = nil
                mode = .signIn
            } label: {
                Text("Back to sign in")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(24)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private var mainAuthCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TabPill(label: "Sign in", isActive: mode == .signIn, ns: ns) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { mode = .signIn; errorMessage = nil }
                }
                TabPill(label: "Create account", isActive: mode == .signUp, ns: ns) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { mode = .signUp; errorMessage = nil }
                }
            }
            .padding(4)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.bottom, 28)

            if mode == .signUp {
                VStack(alignment: .leading, spacing: 8) {
                    Text("I AM A")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .tracking(1.5)
                    HStack(spacing: 10) {
                        RolePill(label: "Doctor", icon: "stethoscope", isSelected: selectedRole == .doctor) {
                            withAnimation(.spring(response: 0.3)) { selectedRole = .doctor }
                        }
                        RolePill(label: "Hospital", icon: "cross.case.fill", isSelected: selectedRole == .hospital) {
                            withAnimation(.spring(response: 0.3)) { selectedRole = .hospital }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            VStack(spacing: 10) {
                Button { startGoogleSignIn() } label: {
                    oauthLabel(systemImage: "globe", title: "Continue with Google")
                }
                .buttonStyle(.plain)
                .disabled(isLoading || !SupabaseAuthService.shared.isConfigured)

                SignInWithAppleButton(.signIn) { request in
                    let nonce = randomNonce()
                    appleNonce = nonce
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = sha256(nonce)
                } onCompletion: { result in
                    handleAppleResult(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .disabled(isLoading || !SupabaseAuthService.shared.isConfigured)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            HStack(spacing: 12) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                Text("OR USE EMAIL").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.white.opacity(0.25)).tracking(1)
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            VStack(spacing: 12) {
                AuthField(icon: "envelope", placeholder: "Email address", text: $email, keyboard: .emailAddress)
                AuthField(icon: "lock", placeholder: "Password", text: $password, isSecure: true)
                if mode == .signUp {
                    AuthField(icon: "lock.fill", placeholder: "Confirm password", text: $confirmPassword, isSecure: true)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 24)
            .animation(.spring(response: 0.35), value: mode)

            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "F87171"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .transition(.opacity)
            }

            if mode == .signIn {
                HStack {
                    Spacer()
                    Button("Forgot password?") {}
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: "4F8EF7").opacity(0.8))
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }

            Button { handleSubmit() } label: {
                authPrimaryLabel(mode == .signIn ? "Sign in" : "Create account")
            }
            .buttonStyle(.plain)
            .disabled(isLoading || email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || (mode == .signUp && confirmPassword.isEmpty))
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }

    private func authPrimaryLabel(_ title: String) -> some View {
        ZStack {
            if isLoading {
                ProgressView().tint(.white)
            } else {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
            LinearGradient(
                colors: [Color(hex: "4F8EF7"), Color(hex: "2563EB")],
                startPoint: .leading, endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private func oauthLabel(systemImage: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.75))
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    #if DEBUG
    private let demoAccounts: [String: (email: String, role: UserRole)] = [
        "erdunn": ("erdunn706@gmail.com", .hospital),
        "erdunn706@gmail.com": ("erdunn706@gmail.com", .hospital),
        "jdunn": ("jdunn@eporthospine.com", .doctor),
        "jdunn@eporthospine": ("jdunn@eporthospine.com", .doctor),
        "jdunn@eporthospine.com": ("jdunn@eporthospine.com", .doctor)
    ]
    private let demoPassword = "1234567890"
    #endif

    private func normalizeEmail(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        #if DEBUG
        if let mapped = demoAccounts[value]?.email { return mapped }
        #endif
        if value == "erdunn" { return "erdunn706@gmail.com" }
        if value == "jdunn" || value == "jdunn@eporthospine" { return "jdunn@eporthospine.com" }
        if value.hasSuffix("@eporthospine") { return value + ".com" }
        return value
    }

    private func finishAuth(userID: UUID, email: String, role: UserRole) {
        SessionStore.shared.beginSession(userID: userID, email: email, role: role)
        let hasProfile = role == .doctor ? DoctorProfile.load() != nil : HospitalProfile.load() != nil
        if hasProfile { auth.completeOnboarding(role: role) } else { auth.selectRole(role) }
    }

    private func startGoogleSignIn() {
        guard SupabaseAuthService.shared.isConfigured else {
            errorMessage = "Supabase is not configured."
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let result = try await SupabaseAuthService.shared.signInWithOAuth(provider: "google", role: selectedRole)
                await MainActor.run {
                    if result.needsMfa {
                        isLoading = false
                        mfaChallenge = true
                        mfaCode = ""
                        email = result.email
                    } else {
                        maybePromptMfaEnroll(
                            thenFinish: result.userID,
                            email: result.email.isEmpty ? "google-user" : result.email,
                            role: result.role,
                            suggest: result.suggestMfaEnroll
                        )
                    }
                }
            } catch AuthServiceError.oauthCancelled {
                await MainActor.run { isLoading = false }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            let ns = error as NSError
            if ns.code == ASAuthorizationError.canceled.rawValue { return }
            errorMessage = error.localizedDescription
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Apple Sign In failed."
                return
            }
            isLoading = true
            errorMessage = nil
            let nonce = appleNonce
            Task {
                do {
                    let result = try await SupabaseAuthService.shared.signInWithAppleIDToken(
                        idToken,
                        nonce: nonce,
                        role: selectedRole
                    )
                    let resolved = result.email.isEmpty ? (credential.email ?? "apple-user") : result.email
                    await MainActor.run {
                        if result.needsMfa {
                            isLoading = false
                            mfaChallenge = true
                            mfaCode = ""
                            email = resolved
                        } else {
                            maybePromptMfaEnroll(
                                thenFinish: result.userID,
                                email: resolved,
                                role: result.role,
                                suggest: result.suggestMfaEnroll
                            )
                        }
                    }
                } catch {
                    await MainActor.run {
                        isLoading = false
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func submitOTP() {
        guard let pending = pendingVerificationEmail else { return }
        let code = otpCode.filter(\.isNumber)
        guard code.count == 6 else {
            errorMessage = "Enter the 6-digit code from your email."
            return
        }
        isLoading = true
        errorMessage = nil
        noticeMessage = nil
        Task {
            do {
                let (userID, role) = try await SupabaseAuthService.shared.verifySignupOTP(
                    email: pending,
                    token: code,
                    role: selectedRole
                )
                await MainActor.run {
                    isLoading = false
                    pendingVerificationEmail = nil
                    otpCode = ""
                    maybePromptMfaEnroll(thenFinish: userID, email: pending, role: role, suggest: true)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleSubmit() {
        errorMessage = nil
        noticeMessage = nil
        pendingVerificationEmail = nil
        let trimmedEmail = normalizeEmail(email)
        guard !trimmedEmail.isEmpty else { errorMessage = "Please enter your email."; return }
        guard password.count >= 6 else { errorMessage = "Password must be at least 6 characters."; return }

        #if DEBUG
        if let demo = demoAccounts[trimmedEmail], password == demoPassword,
           !SupabaseAuthService.shared.isConfigured {
            isLoading = true
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run {
                    isLoading = false
                    finishAuth(userID: UUID(), email: demo.email, role: demo.role)
                }
            }
            return
        }
        #endif

        if SupabaseAuthService.shared.isConfigured {
            isLoading = true
            Task {
                do {
                    if mode == .signUp {
                        guard password == confirmPassword else {
                            await MainActor.run { isLoading = false; errorMessage = "Passwords don't match." }
                            return
                        }
                        let result = try await SupabaseAuthService.shared.signUp(
                            email: trimmedEmail,
                            password: password,
                            role: selectedRole
                        )
                        await MainActor.run {
                            isLoading = false
                            if result.needsEmailVerification {
                                pendingVerificationEmail = trimmedEmail
                                otpCode = ""
                                errorMessage = nil
                                noticeMessage = nil
                            } else {
                                maybePromptMfaEnroll(
                                    thenFinish: result.userID,
                                    email: trimmedEmail,
                                    role: selectedRole,
                                    suggest: true
                                )
                            }
                        }
                    } else {
                        let result = try await SupabaseAuthService.shared.signIn(email: trimmedEmail, password: password)
                        await MainActor.run {
                            if result.needsMfa {
                                isLoading = false
                                mfaChallenge = true
                                mfaCode = ""
                                email = result.email
                                errorMessage = nil
                            } else {
                                maybePromptMfaEnroll(
                                    thenFinish: result.userID,
                                    email: result.email,
                                    role: result.role,
                                    suggest: result.suggestMfaEnroll
                                )
                            }
                        }
                    }
                } catch let urlErr as URLError
                    where [.cannotConnectToHost, .notConnectedToInternet,
                           .networkConnectionLost, .timedOut,
                           .cannotFindHost, .dnsLookupFailed].contains(urlErr.code) {
                    await MainActor.run { isLoading = false }
                    handleLocalAuth(trimmedEmail: trimmedEmail)
                } catch AuthServiceError.emailNotConfirmed {
                    await MainActor.run {
                        isLoading = false
                        pendingVerificationEmail = trimmedEmail
                        otpCode = ""
                        errorMessage = nil
                    }
                } catch {
                    await MainActor.run { isLoading = false; errorMessage = error.localizedDescription }
                }
            }
            return
        }

        handleLocalAuth(trimmedEmail: trimmedEmail)
    }

    private func resendVerification() {
        guard let mail = pendingVerificationEmail else { return }
        isLoading = true
        errorMessage = nil
        noticeMessage = nil
        Task {
            do {
                try await SupabaseAuthService.shared.resendSignupEmail(email: mail)
                await MainActor.run {
                    isLoading = false
                    noticeMessage = "New code sent. Check your inbox."
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleLocalAuth(trimmedEmail: String) {
        if mode == .signUp {
            guard password == confirmPassword else { errorMessage = "Passwords don't match."; return }
            if AccountStore.shared.accountExists(email: trimmedEmail) {
                errorMessage = "Account already exists. Sign in instead."; return
            }
            isLoading = true
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await MainActor.run {
                    isLoading = false
                    let userID = AccountStore.shared.register(email: trimmedEmail, password: password, role: selectedRole)
                    finishAuth(userID: userID, email: trimmedEmail, role: selectedRole)
                }
            }
        } else {
            if !AccountStore.shared.accountExists(email: trimmedEmail) {
                let userID = AccountStore.shared.register(email: trimmedEmail, password: password, role: .doctor)
                finishAuth(userID: userID, email: trimmedEmail, role: .doctor)
                return
            }
            guard AccountStore.shared.passwordMatches(email: trimmedEmail, password: password) else {
                errorMessage = "Incorrect password."; return
            }
            isLoading = true
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await MainActor.run {
                    isLoading = false
                    let role = AccountStore.shared.role(for: trimmedEmail) ?? .doctor
                    let userID = AccountStore.shared.userID(for: trimmedEmail) ?? UUID()
                    finishAuth(userID: userID, email: trimmedEmail, role: role)
                }
            }
        }
    }

    private func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in UInt8.random(in: 0...255) }
            randoms.forEach { random in
                if remaining == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Dev Role Picker

private struct DevRolePickerView: View {
    @ObservedObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundGradient()
                VStack(spacing: 14) {
                    Text("Dev Login — pick a role").font(.headline).foregroundStyle(.secondary)
                    ForEach(UserRole.allCases) { role in
                        Button {
                            auth.selectRole(role)
                            dismiss()
                        } label: {
                            Label(role.rawValue, systemImage: role == .doctor ? "stethoscope" : "cross.case.fill")
                                .font(.headline).frame(maxWidth: .infinity).padding()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding()
            }
            .navigationTitle("Select Role")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
        }
    }
}

// MARK: - Tab Pill

private struct TabPill: View {
    let label: String; let isActive: Bool; let ns: Namespace.ID; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                            .matchedGeometryEffect(id: "tab", in: ns)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Role Pill

private struct RolePill: View {
    let label: String; let icon: String; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color(hex: "4F8EF7") : Color.white.opacity(0.4))
                Text(label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : Color.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? Color(hex: "4F8EF7").opacity(0.15) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isSelected ? Color(hex: "4F8EF7").opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Auth Field

private struct AuthField: View {
    let icon: String; let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var isSecure: Bool = false
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.3))
                .frame(width: 20)
            Group {
                if isSecure && !isRevealed {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .tint(Color(hex: "4F8EF7"))
            if isSecure {
                Button { isRevealed.toggle() } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Animated Mesh Background

private struct MeshBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(hex: "0A0F1E"), Color(hex: "1E3A8A").opacity(0.45), Color(hex: "0A0F1E")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - Color hex init

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int & 0xFF)          / 255
        self.init(red: r, green: g, blue: b)
    }
}

#Preview { AuthView(auth: AuthService.shared) }

// MARK: - Account Store (local fallback when Supabase is not configured)

final class AccountStore {
    static let shared = AccountStore()
    private let key = "accounts_v2"

    struct Account: Codable {
        let id: UUID
        let email: String
        let passwordHash: String
        let role: String
    }

    private var accounts: [Account] {
        get {
            guard let d = UserDefaults.standard.data(forKey: key),
                  let a = try? JSONDecoder().decode([Account].self, from: d) else { return migrateFromV1() }
            return a
        }
        set {
            if let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: key) }
        }
    }

    private func migrateFromV1() -> [Account] {
        struct LegacyAccount: Codable { let email: String; let passwordHash: String; let role: String }
        guard let d = UserDefaults.standard.data(forKey: "accounts_v1"),
              let legacy = try? JSONDecoder().decode([LegacyAccount].self, from: d) else { return [] }
        let migrated = legacy.map { Account(id: UUID(), email: $0.email, passwordHash: $0.passwordHash, role: $0.role) }
        accounts = migrated
        return migrated
    }

    func accountExists(email: String) -> Bool {
        accounts.contains { $0.email.lowercased() == email.lowercased() }
    }

    func passwordMatches(email: String, password: String) -> Bool {
        accounts.first { $0.email.lowercased() == email.lowercased() }?.passwordHash == password
    }

    func role(for email: String) -> UserRole? {
        guard let raw = accounts.first(where: { $0.email.lowercased() == email.lowercased() })?.role else { return nil }
        return UserRole(rawValue: raw)
    }

    func userID(for email: String) -> UUID? {
        accounts.first { $0.email.lowercased() == email.lowercased() }?.id
    }

    @discardableResult
    func register(email: String, password: String, role: UserRole) -> UUID {
        let normalized = email.lowercased()
        if let existing = accounts.first(where: { $0.email == normalized }) {
            return existing.id
        }
        let account = Account(id: UUID(), email: normalized, passwordHash: password, role: role.rawValue)
        var all = accounts
        all.append(account)
        accounts = all
        return account.id
    }
}
