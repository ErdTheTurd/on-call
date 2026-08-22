import Foundation

/// Investor walkthrough accounts — local shortcuts that always work, with or without Supabase.
@MainActor
enum DemoAccounts {
    static let password = "1234567890"

    /// Stable ids so re-login keeps the same local profile / seeded data.
    private static let doctorUserID = UUID(uuidString: "00000000-0000-4000-9000-000000000001")!
    private static let hospitalUserID = UUID(uuidString: "00000000-0000-4000-9000-000000000002")!
    private static let hospitalID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    private static let aliases: [String: (email: String, role: UserRole)] = [
        "erdunn": ("erdunn706@gmail.com", .hospital),
        "erdunn706": ("erdunn706@gmail.com", .hospital),
        "erdunn706@gmail.com": ("erdunn706@gmail.com", .hospital),
        "jdunn": ("jdunn@eporthospine.com", .doctor),
        "jdunn@eporthospine": ("jdunn@eporthospine.com", .doctor),
        "jdunn@eporthospine.com": ("jdunn@eporthospine.com", .doctor),
        "info": ("info@erdanimates.shop", .hospital),
        "info@erdanimates.shop": ("info@erdanimates.shop", .hospital),
        "admin": ("info@erdanimates.shop", .hospital)
    ]

    static func normalize(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let mapped = aliases[value]?.email { return mapped }
        if value.hasSuffix("@eporthospine") { return value + ".com" }
        return value
    }

    static func match(email raw: String, password rawPassword: String) -> (email: String, role: UserRole)? {
        guard InvestorDemo.isEnabled else { return nil }
        let email = normalize(raw)
        let password = rawPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard password == Self.password else { return nil }
        guard let entry = aliases[email] ?? aliases.first(where: { $0.value.email == email })?.value else {
            return nil
        }
        return (entry.email, entry.role)
    }

    /// Signs into a fully seeded local session (profiles + mock coverage).
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
