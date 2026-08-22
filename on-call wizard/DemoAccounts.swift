import Foundation

/// Investor walkthrough helpers — Explore buttons + quiet email shortcuts.
@MainActor
enum DemoAccounts {
    /// Offline / screenshot-kit password for known demo emails.
    static let password = "1234567890"

    private static let doctorUserID = UUID(uuidString: "00000000-0000-4000-9000-000000000001")!
    private static let hospitalUserID = UUID(uuidString: "00000000-0000-4000-9000-000000000002")!
    private static let hospitalID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private static let adminUserID = UUID(uuidString: "00000000-0000-4000-9000-000000000099")!

    private static let aliases: [String: (email: String, role: UserRole)] = [
        "erdunn": ("erdunn706@gmail.com", .hospital),
        "erdunn706": ("erdunn706@gmail.com", .hospital),
        "erdunn706@gmail.com": ("erdunn706@gmail.com", .hospital),
        "jdunn": ("jdunn@eporthospine.com", .doctor),
        "jdunn@eporthospine": ("jdunn@eporthospine.com", .doctor),
        "jdunn@eporthospine.com": ("jdunn@eporthospine.com", .doctor)
    ]

    private static let adminEmails: Set<String> = [
        "info@erdanimates.shop",
        "info",
        "admin"
    ]

    static func normalize(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if adminEmails.contains(value) { return "info@erdanimates.shop" }
        if let mapped = aliases[value]?.email { return mapped }
        if value.hasSuffix("@eporthospine") { return value + ".com" }
        return value
    }

    static func isAdminEmail(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return adminEmails.contains(value) || normalize(value) == "info@erdanimates.shop"
    }

    static func role(forEmail raw: String) -> UserRole? {
        let email = normalize(raw)
        if isAdminEmail(email) { return nil }
        return aliases[email]?.role
            ?? aliases.first(where: { $0.value.email == email })?.value.role
    }

    /// Admin screenshot kit: info@erdanimates.shop + 1234567890
    static func matchAdmin(email raw: String, password rawPassword: String) -> Bool {
        guard InvestorDemo.isEnabled else { return false }
        let password = rawPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        return isAdminEmail(raw) && password == Self.password
    }

    /// Quiet offline shortcut for doctor/hospital demos.
    static func matchOffline(email raw: String, password rawPassword: String) -> (email: String, role: UserRole)? {
        guard InvestorDemo.isEnabled else { return nil }
        if matchAdmin(email: raw, password: rawPassword) { return nil }
        let email = normalize(raw)
        let password = rawPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard password == Self.password else { return nil }
        guard let role = role(forEmail: email) else { return nil }
        return (email, role)
    }

    static func enterAdminShowcase(auth: AuthService) {
        SessionStore.shared.beginSession(
            userID: adminUserID,
            email: "info@erdanimates.shop",
            role: .hospital
        )
        auth.enterAdminShowcase()
    }

    static func enter(email: String, role: UserRole, auth: AuthService) {
        let userID = role == .doctor ? doctorUserID : hospitalUserID
        seedProfile(email: email, role: role, userID: userID)
        SessionStore.shared.beginSession(userID: userID, email: email, role: role)

        if role == .doctor {
            AssignedShiftsStore.shared.seedMockShiftsIfNeeded()
            AssignedShiftsStore.shared.seedMockIncomingTradesIfNeeded()
            DoctorRosterStore.shared.seedMockDoctorsIfNeeded()
        } else if let hospitalID = SessionStore.shared.currentHospitalID {
            InvestorDemo.bootstrapIfNeeded(hospitalID: hospitalID, hospitalName: "Average Hospital")
        }

        auth.completeOnboarding(role: role)
    }

    private static func seedProfile(email: String, role: UserRole, userID: UUID) {
        switch role {
        case .doctor:
            var profile = DoctorProfile(
                id: userID,
                userID: userID,
                firstName: "Jordan",
                lastName: "Dunn",
                credential: .md,
                npi: "1487290365",
                licenseNumber: "A48219",
                licenseState: "CA",
                specialties: ["Orthopedics", "Emergency Medicine"],
                email: email,
                verificationStatus: .verified
            )
            SessionStore.shared.linkDoctorProfile(&profile)
            profile.save()
        case .hospital:
            var profile = HospitalProfile(
                id: hospitalID,
                userID: userID,
                name: "Average Hospital",
                npi: "1902847365",
                email: email,
                verificationStatus: .verified,
                verificationFlags: []
            )
            SessionStore.shared.linkHospitalProfile(&profile)
            profile.save()
        }
    }
}
