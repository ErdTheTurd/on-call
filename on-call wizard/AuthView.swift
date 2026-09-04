import SwiftUI
import AuthenticationServices
import CryptoKit

// MARK: - Auth Screen (Sign In / Sign Up)

struct AuthView: View {
    @ObservedObject var auth: AuthService
    @Environment(\.colorScheme) private var colorScheme
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

    enum AuthMode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case signUp = "Create account"
        var id: String { rawValue }
    }

    private var privacyURL: URL {
        WebsiteConfig.baseURL?.appendingPathComponent("privacypolicy/")
            ?? URL(string: "https://mdshift.net/privacypolicy/")!
    }

    var body: some View {
        ZStack {
            BackgroundGradient()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.title.weight(.semibold))
                                .foregroundStyle(Brand.accent)
                                .accessibilityHidden(true)
                            Text(Brand.appName)
                                .font(.title.weight(.bold))
                                .foregroundStyle(Brand.textPrimary)
                        }
                        Text("Smarter shift scheduling")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Brand.textSecondary)
                    }
                    .padding(.top, 56)
                    .padding(.bottom, 28)
                    .accessibilityElement(children: .combine)

                    if mfaChallenge {
                        mfaChallengeCard
                    } else if let enroll = mfaEnroll {
                        mfaEnrollCard(enroll)
                    } else if pendingVerificationEmail != nil {
                        otpCard
                    } else {
                        mainAuthCard
                    }

                    legalFooter
                        .padding(.horizontal, 32)
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

    private var legalFooter: some View {
        VStack(spacing: 4) {
            Text("By continuing you agree to our")
                .font(.caption)
                .foregroundStyle(Brand.textTertiary)
            HStack(spacing: 4) {
                Link("Privacy Policy", destination: privacyURL)
                    .font(.caption.weight(.semibold))
                Text("and Terms of Service.")
                    .font(.caption)
                    .foregroundStyle(Brand.textTertiary)
            }
            .tint(Brand.accent)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var mfaChallengeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Authenticator code")
                .font(.title2.weight(.bold))
                .foregroundStyle(Brand.textPrimary)
            Text("Open Google Authenticator (or any TOTP app) and enter the 6-digit code for \(Brand.appName).")
                .font(.subheadline)
                .foregroundStyle(Brand.textSecondary)
            codeField(placeholder: "6-digit code", text: $mfaCode) {
                if mfaCode.filter(\.isNumber).count == 6 { submitMfaChallenge() }
            }
            if let err = errorMessage {
                Text(err).font(.subheadline.weight(.medium)).foregroundStyle(Brand.danger)
            }
            Button { submitMfaChallenge() } label: {
                authPrimaryLabel("Verify")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isLoading || mfaCode.filter(\.isNumber).count != 6)
            Button {
                mfaChallenge = false
                mfaCode = ""
                SupabaseAuthService.shared.signOut()
            } label: {
                Text("Back to sign in")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Brand.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .cardStyle()
        .padding(.horizontal, 20)
    }

    private func mfaEnrollCard(_ enroll: SupabaseAuthService.TotpEnrollment) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set up authenticator")
                .font(.title2.weight(.bold))
                .foregroundStyle(Brand.textPrimary)
            Text("Add \(Brand.appName) in Google Authenticator using this secret, then enter the 6-digit code.")
                .font(.subheadline)
                .foregroundStyle(Brand.textSecondary)
            if !enroll.secret.isEmpty {
                Text(enroll.secret)
                    .font(.body.weight(.semibold).monospaced())
                    .foregroundStyle(Brand.accent)
                    .textSelection(.enabled)
            }
            codeField(placeholder: "6-digit code", text: $mfaCode) {
                if mfaCode.filter(\.isNumber).count == 6 { confirmMfaEnroll() }
            }
            if let err = errorMessage {
                Text(err).font(.subheadline.weight(.medium)).foregroundStyle(Brand.danger)
            }
            Button { confirmMfaEnroll() } label: {
                authPrimaryLabel("Confirm and continue")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isLoading || mfaCode.filter(\.isNumber).count != 6)
            Button { skipMfaEnroll() } label: {
                Text("Skip for now")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.accent)
                    .frame(maxWidth: .infinity)
            }
        }
        .cardStyle()
        .padding(.horizontal, 20)
    }

    private func codeField(placeholder: String, text: Binding<String>, onComplete: @escaping () -> Void) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .multilineTextAlignment(.center)
            .font(.title.weight(.semibold))
            .foregroundStyle(Brand.textPrimary)
            .padding(.vertical, 14)
            .background(Brand.surfaceHigh, in: RoundedRectangle(cornerRadius: Brand.buttonRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Brand.buttonRadius, style: .continuous)
                    .strokeBorder(Brand.border, lineWidth: 1)
            )
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
                .font(.title2.weight(.bold))
                .foregroundStyle(Brand.textPrimary)
            Text("We sent a 6-digit code to \(pendingVerificationEmail ?? ""). Enter it here — no link to click.")
                .font(.subheadline)
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("", text: $otpCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.title.weight(.semibold))
                .foregroundStyle(Brand.textPrimary)
                .padding(.vertical, 14)
                .background(Brand.surfaceHigh, in: RoundedRectangle(cornerRadius: Brand.buttonRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.buttonRadius, style: .continuous)
                        .strokeBorder(Brand.border, lineWidth: 1)
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
                .accessibilityLabel("Verification code")

            if let err = errorMessage {
                Text(err)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Brand.danger)
            }
            if let notice = noticeMessage {
                Text(notice)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Brand.success)
            }

            Button { submitOTP() } label: {
                authPrimaryLabel("Verify and continue")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isLoading || otpCode.count != 6)

            Button { resendVerification() } label: {
                Text("Resend code")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.accent)
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
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Brand.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .cardStyle()
        .padding(.horizontal, 20)
    }

    private var mainAuthCard: some View {
        VStack(spacing: 0) {
            Picker("Account mode", selection: $mode) {
                ForEach(AuthMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .onChange(of: mode) { _, _ in errorMessage = nil }

            VStack(alignment: .leading, spacing: 8) {
                Text("I am a")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.textTertiary)
                    .textCase(.uppercase)
                Picker("Role", selection: $selectedRole) {
                    Text("Doctor").tag(UserRole.doctor)
                    Text("Hospital").tag(UserRole.hospital)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Account role")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            VStack(spacing: 10) {
                Button { startGoogleSignIn() } label: {
                    oauthLabel(systemImage: "globe", title: "Continue with Google")
                }
                .buttonStyle(.plain)
                .disabled(isLoading || !SupabaseAuthService.shared.isConfigured)
                .accessibilityLabel("Continue with Google")

                SignInWithAppleButton(.signIn) { request in
                    let nonce = randomNonce()
                    appleNonce = nonce
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = sha256(nonce)
                } onCompletion: { result in
                    handleAppleResult(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: Brand.buttonRadius, style: .continuous))
                .disabled(isLoading || !SupabaseAuthService.shared.isConfigured)
                .opacity(isLoading || !SupabaseAuthService.shared.isConfigured ? 0.5 : 1)
                .allowsHitTesting(!isLoading && SupabaseAuthService.shared.isConfigured)
                .accessibilityLabel("Continue with Apple")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            HStack(spacing: 12) {
                Rectangle().fill(Brand.border).frame(height: 1)
                Text("OR USE EMAIL")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.textTertiary)
                Rectangle().fill(Brand.border).frame(height: 1)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            VStack(spacing: 12) {
                AuthField(
                    icon: "envelope",
                    placeholder: "Email address",
                    text: $email,
                    keyboard: .emailAddress,
                    textContentType: .emailAddress
                )
                AuthField(
                    icon: "lock",
                    placeholder: "Password",
                    text: $password,
                    isSecure: true,
                    textContentType: mode == .signUp ? .newPassword : .password
                )
                if mode == .signUp {
                    AuthField(
                        icon: "lock.fill",
                        placeholder: "Confirm password",
                        text: $confirmPassword,
                        isSecure: true,
                        textContentType: .newPassword
                    )
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.2), value: mode)

            if let err = errorMessage {
                Text(err)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Brand.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .transition(.opacity)
            }

            Button { handleSubmit() } label: {
                authPrimaryLabel(mode == .signIn ? "Sign in" : "Create account")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isLoading || email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || (mode == .signUp && confirmPassword.isEmpty))
            .padding(.horizontal, 24)
            .padding(.top, 20)

            if InvestorDemo.isEnabled && mode == .signIn {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Rectangle().fill(Brand.border).frame(height: 1)
                        Text("OR LOOK AROUND FIRST")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.textTertiary)
                        Rectangle().fill(Brand.border).frame(height: 1)
                    }
                    .padding(.top, 4)
                    Button {
                        DemoAccounts.enter(email: "jdunn@eporthospine.com", role: .doctor, auth: auth)
                    } label: {
                        oauthLabel(systemImage: "stethoscope", title: "Explore as a doctor")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Explore as a doctor with sample data")
                    Button {
                        DemoAccounts.enter(email: "erdunn706@gmail.com", role: .hospital, auth: auth)
                    } label: {
                        oauthLabel(systemImage: "cross.case.fill", title: "Explore as a hospital")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Explore as a hospital with sample data")
                    Text("Sample data, no account needed.")
                        .font(.caption)
                        .foregroundStyle(Brand.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }

            Color.clear.frame(height: 20)
        }
        .cardStyle()
        .padding(.horizontal, 20)
    }

    private func authPrimaryLabel(_ title: String) -> some View {
        ZStack {
            if isLoading {
                ProgressView().tint(.white)
            } else {
                Text(title)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func oauthLabel(systemImage: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(Brand.textSecondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(Brand.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .frame(minHeight: 50)
        .background(Brand.surfaceHigh, in: RoundedRectangle(cornerRadius: Brand.buttonRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Brand.buttonRadius, style: .continuous)
                .strokeBorder(Brand.border, lineWidth: 1)
        )
    }

    // Investor demo aliases live in `DemoAccounts`.

    private func normalizeEmail(_ raw: String) -> String {
        DemoAccounts.normalize(raw)
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
            if ns.domain == ASAuthorizationError.errorDomain,
               ns.code == ASAuthorizationError.canceled.rawValue { return }
            if ns.domain == ASAuthorizationError.errorDomain,
               ns.code == ASAuthorizationError.unknown.rawValue {
                // Common on first-run / iPad when the sheet dismisses oddly — don't block review with a cryptic code.
                errorMessage = "Apple Sign In did not complete. Try again, or use Explore as a doctor / hospital."
                return
            }
            errorMessage = error.localizedDescription
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Apple Sign In failed. Try Explore as a doctor / hospital, or email sign-in."
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
                    let resolved = result.email.isEmpty
                        ? (credential.email ?? "apple-user-\(result.userID.uuidString.prefix(8))@privaterelay.appleid.com")
                        : result.email
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

        // Demo / App Store accounts always open the seeded walkthrough first — never
        // Supabase MFA, OTP, or empty profiles for known investor credentials.
        if mode == .signIn {
            if DemoAccounts.matchAdmin(email: email, password: password) {
                DemoAccounts.enterAdminShowcase(auth: auth)
                return
            }
            if let demo = DemoAccounts.matchOffline(email: email, password: password) {
                DemoAccounts.enter(email: demo.email, role: demo.role, auth: auth)
                return
            }
        }

        // Prefer real Supabase auth for everyone else. Seeded local demos are also
        // Explore buttons, or a quiet fallback when the network / password fails.
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
                                if enterDemoFallbackIfPossible(email: trimmedEmail) { return }
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
                                    suggest: false
                                )
                            }
                        }
                    }
                } catch let urlErr as URLError
                    where [.cannotConnectToHost, .notConnectedToInternet,
                           .networkConnectionLost, .timedOut,
                           .cannotFindHost, .dnsLookupFailed].contains(urlErr.code) {
                    await MainActor.run {
                        if enterDemoFallbackIfPossible(email: trimmedEmail) { return }
                        isLoading = false
                        handleLocalAuth(trimmedEmail: trimmedEmail)
                    }
                } catch AuthServiceError.emailNotConfirmed {
                    await MainActor.run {
                        // Mid-demo: don't strand investors on OTP — open the seeded walkthrough.
                        if enterDemoFallbackIfPossible(email: trimmedEmail) { return }
                        isLoading = false
                        pendingVerificationEmail = trimmedEmail
                        otpCode = ""
                        errorMessage = nil
                    }
                } catch {
                    await MainActor.run {
                        if enterDemoFallbackIfPossible(email: trimmedEmail) { return }
                        isLoading = false
                        errorMessage = error.localizedDescription
                    }
                }
            }
            return
        }

        if let demo = DemoAccounts.matchOffline(email: email, password: password) {
            DemoAccounts.enter(email: demo.email, role: demo.role, auth: auth)
            return
        }

        handleLocalAuth(trimmedEmail: trimmedEmail)
    }

    /// If this is a known investor email, open the seeded demo instead of a hard error.
    @discardableResult
    private func enterDemoFallbackIfPossible(email: String) -> Bool {
        guard InvestorDemo.isEnabled else { return false }
        if DemoAccounts.isAdminEmail(email) {
            isLoading = false
            DemoAccounts.enterAdminShowcase(auth: auth)
            return true
        }
        guard let role = DemoAccounts.role(forEmail: email) else { return false }
        isLoading = false
        DemoAccounts.enter(email: DemoAccounts.normalize(email), role: role, auth: auth)
        return true
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

// MARK: - Auth Field

private struct AuthField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var isSecure: Bool = false
    var textContentType: UITextContentType? = nil
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(Brand.textTertiary)
                .frame(width: 20)
                .accessibilityHidden(true)
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
            .font(.body)
            .foregroundStyle(Brand.textPrimary)
            .tint(Brand.accent)
            .textContentType(textContentType)
            if isSecure {
                Button { isRevealed.toggle() } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.body)
                        .foregroundStyle(Brand.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRevealed ? "Hide password" : "Show password")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 50)
        .background(Brand.surfaceHigh, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Brand.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
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
