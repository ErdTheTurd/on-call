import SwiftUI

// MARK: - Doctor Onboarding Flow

struct DoctorOnboardingView: View {
    var onComplete: (DoctorProfile) -> Void

    @State private var step = 0
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var credential: DoctorProfile.CredentialType = .md
    @State private var npi = ""
    @State private var deaNumber = ""
    @State private var licenseNumber = ""
    @State private var licenseState = ""
    @State private var email = ""
    @State private var selectedSpecialties: Set<String> = []

    // Email verification
    @State private var sentCode = ""
    @State private var enteredCode = ""
    @State private var isSendingCode = false
    @State private var codeSent = false
    @State private var codeVerified = false
    @State private var codeError: String? = nil

    // NPI verification
    @State private var isVerifying = false
    @State private var verificationResult: DoctorVerificationResult? = nil
    @State private var verificationError: String? = nil
    @State private var npiAutoFilledName: String? = nil

    private let totalSteps = 4

    var body: some View {
        ZStack {
            BackgroundGradient()
            VStack(spacing: 0) {
                // Progress bar
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
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: stepIcon)
                                .font(.system(size: 44, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.accentColor)
                                .padding(.top, 32)
                            Text(stepTitle)
                                .font(.system(.title2, design: .rounded, weight: .bold))
                            Text(stepSubtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }

                        Group {
                            switch step {
                            case 0: Step1View(firstName: $firstName, lastName: $lastName, credential: $credential)
                            case 1: Step2View(
                                        npi: $npi, deaNumber: $deaNumber,
                                        licenseNumber: $licenseNumber, licenseState: $licenseState,
                                        email: $email,
                                        isVerifying: $isVerifying,
                                        verificationResult: $verificationResult,
                                        verificationError: $verificationError,
                                        npiAutoFilledName: $npiAutoFilledName,
                                        firstName: firstName, lastName: lastName,
                                        credential: credential.rawValue,
                                        onVerify: runVerification
                                    )
                            case 2: EmailVerificationStep(
                                        email: email,
                                        sentCode: $sentCode,
                                        enteredCode: $enteredCode,
                                        isSendingCode: $isSendingCode,
                                        codeSent: $codeSent,
                                        codeVerified: $codeVerified,
                                        codeError: $codeError,
                                        recipientName: "\(firstName) \(lastName)",
                                        onSend: sendVerificationCode,
                                        onVerify: verifyCode
                                    )
                            case 3: Step3View(
                                        selectedSpecialties: $selectedSpecialties,
                                        npiTaxonomy: verificationResult?.npiRecord?.taxonomyDescription
                                    )
                            default: EmptyView()
                            }
                        }
                        .padding(.horizontal)

                        HStack(spacing: 12) {
                            if step > 0 {
                                Button("Back") { withAnimation { step -= 1 } }
                                    .buttonStyle(.bordered).tint(.secondary)
                            }
                            Button(step < totalSteps - 1 ? "Continue" : "Get Started") {
                                if step < totalSteps - 1 { withAnimation { step += 1 } }
                                else { finishOnboarding() }
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!stepValid || isVerifying || isSendingCode)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Email Code

    private func sendVerificationCode() {
        isSendingCode = true
        codeError = nil
        let code = EmailVerificationStore.shared.issue(for: email)
        sentCode = code
        Task {
            do {
                try await SendGridService.shared.sendVerificationCode(
                    to: email, code: code,
                    recipientName: "\(firstName) \(lastName)"
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

    // MARK: - NPI Verification

    private func runVerification() {
        isVerifying = true; verificationResult = nil; verificationError = nil
        Task {
            let result = await DoctorVerificationService.shared.verify(
                firstName: firstName, lastName: lastName,
                credential: credential.rawValue,
                npi: npi, licenseNumber: licenseNumber,
                licenseState: licenseState, email: email
            )
            await MainActor.run {
                isVerifying = false
                verificationResult = result
                if let record = result.npiRecord {
                    npiAutoFilledName = "\(record.firstName) \(record.lastName), \(record.credential)"
                }
                verificationError = result.finalStatus == .flagged ? result.flags.first : nil
            }
        }
    }

    // MARK: - Step metadata

    private var stepIcon: String   { ["person.crop.circle.badge.plus","doc.text.fill","envelope.badge.fill","cross.case.fill"][step] }
    private var stepTitle: String  { ["Who are you?","Verify Credentials","Confirm Email","Your Specialties"][step] }
    private var stepSubtitle: String {
        [
            "Enter your name and credential type.",
            "We check NPI, DEA#, license, and malpractice with federal registries.",
            "Enter the 6-digit code we sent to your email.",
            "Select all specialties you're qualified to cover."
        ][step]
    }

    private var stepValid: Bool {
        switch step {
        case 0: return !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
                       !lastName.trimmingCharacters(in: .whitespaces).isEmpty
        case 1:
            guard npi.count == 10, !licenseNumber.isEmpty, licenseState.count == 2, !email.isEmpty else { return false }
            return verificationResult != nil && verificationResult?.npiRecord != nil
        case 2: return codeVerified
        case 3: return !selectedSpecialties.isEmpty
        default: return false
        }
    }

    private func finishOnboarding() {
        let result = verificationResult
        var profile = DoctorProfile(
            userID: SessionStore.shared.currentUserID,
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            credential: credential,
            npi: npi, deaNumber: deaNumber,
            licenseNumber: licenseNumber.trimmingCharacters(in: .whitespaces),
            licenseState: licenseState.uppercased().trimmingCharacters(in: .whitespaces),
            specialties: Array(selectedSpecialties).sorted(),
            email: email.lowercased().trimmingCharacters(in: .whitespaces),
            verificationStatus: result?.finalStatus ?? .flagged,
            verificationFlags: result?.flags ?? [],
            npiRegistryName: result?.npiRecord.map { "\($0.firstName) \($0.lastName)" },
            npiTaxonomy: result?.npiRecord?.taxonomyDescription
        )
        SessionStore.shared.linkDoctorProfile(&profile)
        profile.save()
        DoctorRosterStore.shared.registerDoctor(profile)
        Task { await SupabaseProfileSync.upsertDoctor(profile) }
        onComplete(profile)
    }
}

// MARK: - Step 1: Name & Credential

private struct Step1View: View {
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var credential: DoctorProfile.CredentialType

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                OnboardingField(label: "First Name", text: $firstName, placeholder: "Jane")
                Divider()
                OnboardingField(label: "Last Name",  text: $lastName,  placeholder: "Smith")
            }
            .cardStyle()

            VStack(alignment: .leading, spacing: 10) {
                Text("Credential Type").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(DoctorProfile.CredentialType.allCases) { cred in
                        CredentialChip(label: cred.rawValue, isSelected: credential == cred) { credential = cred }
                    }
                }
            }
            .cardStyle()
        }
    }
}

// MARK: - Step 2: Credentials

private struct Step2View: View {
    @Binding var npi: String
    @Binding var deaNumber: String
    @Binding var licenseNumber: String
    @Binding var licenseState: String
    @Binding var email: String
    @Binding var isVerifying: Bool
    @Binding var verificationResult: DoctorVerificationResult?
    @Binding var verificationError: String?
    @Binding var npiAutoFilledName: String?

    let firstName: String
    let lastName: String
    let credential: String
    let onVerify: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                OnboardingField(label: "NPI Number", text: $npi, placeholder: "10 digits", keyboard: .numberPad)
                    .onChange(of: npi) { _, new in npi = String(new.filter { $0.isNumber }.prefix(10)) }
                if let autoName = npiAutoFilledName {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill").foregroundStyle(Color.accentColor)
                        Text("Registry: \(autoName)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                OnboardingField(label: "DEA #", text: $deaNumber, placeholder: "AB1234567")
                Divider()
                OnboardingField(label: "License #", text: $licenseNumber, placeholder: "A1234567")
                Divider()
                HStack {
                    Text("State")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 90, alignment: .leading)
                    TextField("TX", text: $licenseState)
                        .font(.body)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .onChange(of: licenseState) { _, new in
                            licenseState = String(new.filter { $0.isLetter }.prefix(2)).uppercased()
                        }
                }
                Divider()
                OnboardingField(label: "Work Email", text: $email, placeholder: "jane@hospital.org", keyboard: .emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .cardStyle()

            Button { onVerify() } label: {
                Group {
                    if isVerifying {
                        HStack(spacing: 10) { ProgressView().tint(.white); Text("Checking NPI Registry…") }
                    } else {
                        Label("Verify Credentials", systemImage: "checkmark.shield.fill")
                    }
                }
                .font(.headline).frame(maxWidth: .infinity).padding()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(npi.count < 10 || licenseNumber.isEmpty || licenseState.count < 2 || email.isEmpty || isVerifying)

            if let result = verificationResult { VerificationBanner(result: result) }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield.fill").foregroundStyle(Color.accentColor)
                Text("We cross-reference NPI, DEA, and state license with federal registries. Your documents are reviewed once and then deleted.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .cardStyle()
        }
    }
}

// MARK: - Email Verification Step

struct EmailVerificationStep: View {
    let email: String
    @Binding var sentCode: String
    @Binding var enteredCode: String
    @Binding var isSendingCode: Bool
    @Binding var codeSent: Bool
    @Binding var codeVerified: Bool
    @Binding var codeError: String?
    let recipientName: String
    let onSend: () -> Void
    let onVerify: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if codeVerified {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                    Text("Email Verified!")
                        .font(.title2.bold())
                    Text(email).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .cardStyle()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "envelope.fill").foregroundStyle(Color.accentColor)
                        Text("Sending to:").foregroundStyle(.secondary)
                        Text(email).font(.subheadline.weight(.medium))
                    }
                    .font(.subheadline)

                    if !codeSent {
                        Button { onSend() } label: {
                            Group {
                                if isSendingCode { HStack(spacing: 10) { ProgressView().tint(.white); Text("Sending…") } }
                                else { Label("Send Verification Code", systemImage: "paperplane.fill") }
                            }
                            .font(.headline).frame(maxWidth: .infinity).padding()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isSendingCode)

                        VStack(spacing: 6) {
                            Button {
                                withAnimation { codeVerified = true; codeError = nil }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.forward.circle")
                                    Text("Skip this step")
                                }
                                .font(.footnote.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(.secondary)
                        }
                    } else {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter the 6-digit code from your email")
                                .font(.subheadline.weight(.medium))
                            TextField("000000", text: $enteredCode)
                                .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                                .multilineTextAlignment(.center)
                                .keyboardType(.numberPad)
                                .onChange(of: enteredCode) { _, new in
                                    enteredCode = String(new.filter { $0.isNumber }.prefix(6))
                                }
                                .frame(height: 56)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }

                        if let err = codeError {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }

                        HStack(spacing: 12) {
                            Button("Resend") { onSend() }
                                .buttonStyle(.bordered)
                                .disabled(isSendingCode)
                            Button { onVerify() } label: {
                                Text("Verify").font(.headline).frame(maxWidth: .infinity).padding()
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(enteredCode.count < 6)
                        }
                    }
                }
                .cardStyle()

                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill").foregroundStyle(Color.accentColor)
                    Text("During development all codes are redirected to erdunn706@gmail.com.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .cardStyle()
            }
        }
    }
}

// MARK: - Step 3: Specialties

private struct Step3View: View {
    @Binding var selectedSpecialties: Set<String>
    let npiTaxonomy: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let taxonomy = npiTaxonomy {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                    Text("Registry shows: \(taxonomy)").font(.caption).foregroundStyle(.secondary)
                }
                .cardStyle()
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(DemoData.specialties, id: \.self) { specialty in
                    let isSelected = selectedSpecialties.contains(specialty)
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            if isSelected { selectedSpecialties.remove(specialty) } else { selectedSpecialties.insert(specialty) }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            Text(specialty).font(.subheadline).lineLimit(1)
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Verification Banner

struct VerificationBanner: View {
    let result: DoctorVerificationResult

    var statusColor: Color {
        switch result.finalStatus {
        case .pending:  return .green
        case .flagged:  return .orange
        case .verified: return .green
        default:        return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: result.finalStatus.systemImage).foregroundStyle(statusColor).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.finalStatus == .pending ? "Verification Submitted" : "Needs Manual Review").font(.headline)
                    Text(result.finalStatus == .pending
                         ? "Automated checks passed. Team reviews within 24–48h."
                         : "Some checks didn't match. You can continue — our team will review.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
                CheckRow(label: "NPI found in federal registry",  passed: result.npiRecord != nil)
                CheckRow(label: "Name matches registry",           passed: result.nameMatches)
                CheckRow(label: "Credential type matches",         passed: result.credentialMatches)
                CheckRow(label: "Institutional email",             passed: result.emailDomainValid)
            }
        }
        .cardStyle()
        .overlay(RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous).strokeBorder(statusColor.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Shared Components

struct OnboardingField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack {
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(.secondary).frame(minWidth: 90, alignment: .leading)
            TextField(placeholder, text: $text).keyboardType(keyboard).font(.body)
        }
    }
}

struct CredentialChip: View {
    let label: String; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.1)))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

struct CheckRow: View {
    let label: String; let passed: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(passed ? Color.green : Color.red).font(.caption)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

#Preview { DoctorOnboardingView { _ in } }

