import SwiftUI

// MARK: - Hospital Onboarding Flow

struct HospitalOnboardingView: View {
    var onComplete: (HospitalProfile) -> Void

    /// Prefill only — hospitals must still enter a facility work email (not personal / Apple relay).
    private let suggestedEmail: String

    @State private var step = 0
    @State private var hospitalName = ""
    @State private var npi = ""
    @State private var email: String

    @State private var isVerifying = false
    @State private var verificationResult: HospitalVerificationResult? = nil
    @State private var npiAutoFilledName: String? = nil

    @State private var sentCode = ""
    @State private var enteredCode = ""
    @State private var isSendingCode = false
    @State private var codeSent = false
    @State private var codeVerified = false
    @State private var codeError: String? = nil

    private let totalSteps = 2

    init(initialEmail: String = "", onComplete: @escaping (HospitalProfile) -> Void) {
        self.onComplete = onComplete
        let mail = initialEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        self.suggestedEmail = mail
        // Prefer empty so the user types a hospital work address; keep Apple email only as placeholder hint.
        let isInstitutional = (try? EmailDomainChecker.validate(mail)) != nil
        _email = State(initialValue: isInstitutional ? mail : "")
    }

    var body: some View {
        ZStack {
            BackgroundGradient()
            VStack(spacing: 0) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.secondary.opacity(0.15))
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(step + 1) / CGFloat(totalSteps))
                            .animation(.spring(response: 0.4), value: step)
                    }
                }
                .frame(height: 3)

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Image(systemName: step == 0 ? "cross.case.fill" : "envelope.badge.fill")
                                .font(.system(size: 44, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.accentColor)
                                .padding(.top, 32)
                            Text(step == 0 ? "Verify Your Facility" : "Confirm Work Email")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                            Text(step == 0
                                 ? "Enter your hospital name, facility NPI, and institutional work email."
                                 : "Enter the 6-digit code we sent to your hospital email.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }

                        if step == 0 {
                            facilityStep
                        } else {
                            EmailVerificationStep(
                                email: email,
                                sentCode: $sentCode,
                                enteredCode: $enteredCode,
                                isSendingCode: $isSendingCode,
                                codeSent: $codeSent,
                                codeVerified: $codeVerified,
                                codeError: $codeError,
                                recipientName: hospitalName,
                                onSend: sendVerificationCode,
                                onVerify: verifyCode
                            )
                            .padding(.horizontal)
                        }

                        HStack {
                            if step > 0 {
                                Button("Back") { withAnimation { step = 0 } }
                                    .buttonStyle(.bordered)
                            }
                            Spacer()
                            if step == 0 {
                                Button("Continue") {
                                    withAnimation { step = 1 }
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(!step0Valid)
                            } else {
                                Button("Continue to Dashboard") {
                                    finishOnboarding()
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(!codeVerified || isVerifying)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var facilityStep: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                OnboardingField(label: "Hospital Name", text: $hospitalName, placeholder: "Average Hospital")
                Divider()
                OnboardingField(label: "Facility NPI", text: $npi, placeholder: "10-digit org NPI", keyboard: .numberPad)
                    .onChange(of: npi) { _, new in npi = String(new.filter { $0.isNumber }.prefix(10)) }

                if let autoName = npiAutoFilledName {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill").foregroundStyle(Color.accentColor)
                        Text("Registry: \(autoName)").font(.caption).foregroundStyle(.secondary)
                    }
                }

                Divider()
                OnboardingField(
                    label: "Hospital Work Email",
                    text: $email,
                    placeholder: "admin@yourhospital.org",
                    keyboard: .emailAddress
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Text("Use an email on your hospital’s domain — not Gmail, iCloud, or Apple Hide My Email.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !suggestedEmail.isEmpty && suggestedEmail.lowercased() != email.lowercased() {
                    Text("Signed in as \(suggestedEmail). Facility contact email above can differ.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .cardStyle()
            .padding(.horizontal)

            Button { runVerification() } label: {
                Group {
                    if isVerifying {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Checking NPI Registry…")
                        }
                    } else {
                        Label("Verify Facility", systemImage: "building.2.fill")
                    }
                }
                .font(.headline).frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(npi.count < 10 || hospitalName.isEmpty || email.isEmpty || isVerifying)
            .padding(.horizontal)

            if let result = verificationResult {
                HospitalVerificationBanner(result: result, showEmailDomainCheck: true)
                    .padding(.horizontal)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield.fill").foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Why we verify").font(.caption.weight(.semibold))
                    Text("We check your facility NPI in the CMS registry and require a hospital work email. After you verify that email, our team will contact you to finish activation.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .cardStyle()
            .padding(.horizontal)
        }
    }

    private var step0Valid: Bool {
        guard npi.count == 10, !hospitalName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard (try? EmailDomainChecker.validate(email)) != nil else { return false }
        return verificationResult?.npiRecord != nil && verificationResult?.emailDomainValid == true
    }

    private func runVerification() {
        isVerifying = true
        verificationResult = nil
        Task {
            let result = await HospitalVerificationService.shared.verify(
                hospitalName: hospitalName,
                npi: npi,
                email: email,
                emailProvidedByApple: false
            )
            await MainActor.run {
                isVerifying = false
                verificationResult = result
                npiAutoFilledName = result.npiRecord?.organizationName
            }
        }
    }

    private func sendVerificationCode() {
        isSendingCode = true
        codeError = nil
        let code = EmailVerificationStore.shared.issue(for: email)
        sentCode = code
        Task {
            do {
                try await SendGridService.shared.sendVerificationCode(
                    to: email, code: code, recipientName: hospitalName
                )
                await MainActor.run { isSendingCode = false; codeSent = true }
            } catch {
                await MainActor.run {
                    isSendingCode = false
                    codeError = error.localizedDescription
                }
            }
        }
    }

    private func verifyCode() {
        if EmailVerificationStore.shared.validate(email: email, code: enteredCode) {
            withAnimation { codeVerified = true; codeError = nil }
        } else {
            codeError = "Incorrect or expired code. Try resending."
        }
    }

    private func finishOnboarding() {
        guard let result = verificationResult, codeVerified else { return }
        let trimmedEmail = email.lowercased().trimmingCharacters(in: .whitespaces)
        var profile = HospitalProfile(
            userID: SessionStore.shared.currentUserID,
            name: hospitalName.trimmingCharacters(in: .whitespaces),
            npi: npi,
            email: trimmedEmail,
            verificationStatus: result.finalStatus,
            verificationFlags: result.flags,
            npiRegistryName: result.npiRecord?.organizationName
        )
        SessionStore.shared.linkHospitalProfile(&profile)
        profile.save()
        SchedulingPolicyStore.shared.setPolicy(profile.schedulingPolicy, for: profile.id)
        Services.hospital.ensureDailyShifts(
            from: Date(),
            days: 120,
            hospitalID: profile.id,
            hospitalName: profile.name,
            policy: profile.schedulingPolicy
        )
        Task {
            await SupabaseProfileSync.upsertHospital(profile)
            for shift in Services.hospital.shifts.filter({ $0.hospitalID == profile.id }).prefix(200) {
                try? await Repositories.shifts.upsert(shift)
            }
            await SendGridService.shared.notifyHospitalSignup(
                hospitalName: profile.name,
                hospitalEmail: trimmedEmail,
                npi: profile.npi,
                flags: profile.verificationFlags
            )
        }
        onComplete(profile)
    }
}

// MARK: - Hospital Verification Banner

struct HospitalVerificationBanner: View {
    let result: HospitalVerificationResult
    var showEmailDomainCheck: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: result.finalStatus.systemImage)
                    .foregroundStyle(statusColor)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bannerTitle).font(.headline)
                    Text(bannerSubtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !result.flags.isEmpty {
                Divider()
                ForEach(result.flags, id: \.self) { flag in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).font(.caption).padding(.top, 1)
                        Text(flag).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 6) {
                CheckRow(label: "Facility NPI found in federal registry", passed: result.npiRecord != nil)
                CheckRow(label: "Facility name matches registry",          passed: result.nameMatches)
                if showEmailDomainCheck {
                    CheckRow(label: "Institutional email domain",              passed: result.emailDomainValid)
                }
            }
        }
        .cardStyle()
        .overlay(
            RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                .strokeBorder(statusColor.opacity(0.4), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        result.finalStatus == .pending ? .green : .orange
    }
    private var bannerTitle: String {
        result.finalStatus == .pending ? "Verification Submitted" : "Needs Manual Review"
    }
    private var bannerSubtitle: String {
        result.finalStatus == .pending
            ? "Automated checks passed. Confirm your email next — our team will contact you within 24–48 hours."
            : "Some checks didn't pass. Confirm your email — our team will review before activation."
    }
}
