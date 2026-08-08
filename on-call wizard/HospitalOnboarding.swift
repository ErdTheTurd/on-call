import SwiftUI

// MARK: - Hospital Onboarding Flow

struct HospitalOnboardingView: View {
    var onComplete: (HospitalProfile) -> Void

    @State private var hospitalName = ""
    @State private var npi = ""
    @State private var email = ""

    @State private var isVerifying = false
    @State private var verificationResult: HospitalVerificationResult? = nil
    @State private var npiAutoFilledName: String? = nil

    var body: some View {
        ZStack {
            BackgroundGradient()
            VStack(spacing: 0) {
                // Single-step progress bar (full)
                Color.accentColor.frame(height: 3)

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(spacing: 8) {
                            Image(systemName: "cross.case.fill")
                                .font(.system(size: 44, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.accentColor)
                                .padding(.top, 32)
                            Text("Verify Your Facility")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                            Text("We look up your facility NPI in the federal registry and verify your institutional email.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }

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
                            OnboardingField(label: "Admin Email", text: $email, placeholder: "admin@averagehospital.org", keyboard: .emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .cardStyle()
                        .padding(.horizontal)

                        // Verify button
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

                        // Result banner
                        if let result = verificationResult {
                            HospitalVerificationBanner(result: result)
                                .padding(.horizontal)
                        }

                        // Security note
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lock.shield.fill").foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Why we verify").font(.caption.weight(.semibold))
                                Text("We cross-reference your facility NPI in the CMS NPPES registry and confirm your admin email matches your facility's domain. Accounts that don't match are reviewed by our team before activation.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .cardStyle()
                        .padding(.horizontal)

                        // Continue button
                        Button("Continue to Dashboard") {
                            finishOnboarding()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(verificationResult == nil || isVerifying)
                        .padding(.horizontal)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func runVerification() {
        isVerifying = true
        verificationResult = nil

        Task {
            let result = await HospitalVerificationService.shared.verify(
                hospitalName: hospitalName,
                npi: npi,
                email: email
            )
            await MainActor.run {
                isVerifying = false
                verificationResult = result
                npiAutoFilledName = result.npiRecord?.organizationName
            }
        }
    }

    private func finishOnboarding() {
        guard let result = verificationResult else { return }
        var profile = HospitalProfile(
            userID: SessionStore.shared.currentUserID,
            name: hospitalName.trimmingCharacters(in: .whitespaces),
            npi: npi,
            email: email.lowercased().trimmingCharacters(in: .whitespaces),
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
        onComplete(profile)
    }
}

// MARK: - Hospital Verification Banner

struct HospitalVerificationBanner: View {
    let result: HospitalVerificationResult

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
                CheckRow(label: "Institutional email domain",              passed: result.emailDomainValid)
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
            ? "Automated checks passed. Our team will review within 24–48 hours."
            : "Some checks didn't pass. You can still continue — our team will review your account before it goes live."
    }
}

// CheckRow is defined in DoctorOnboarding.swift — shared
