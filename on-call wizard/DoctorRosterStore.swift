import Foundation
import Combine

// MARK: - Doctor Roster Store (hospital credentialed doctors)

@MainActor
public final class DoctorRosterStore: ObservableObject {
    public static let shared = DoctorRosterStore()

    private let storageKey = "doctor_roster_v1"
    @Published public private(set) var doctors: [DoctorSummary] = []

    private init() { load() }

    public func registerDoctor(_ profile: DoctorProfile) {
        let summary = DoctorSummary(
            id: profile.id,
            name: "\(profile.firstName) \(profile.lastName)",
            credential: profile.credential.rawValue,
            specialty: profile.specialties.first ?? "Internal Medicine",
            npi: profile.npi,
            isAutoApproved: false,
            verificationStatus: profile.verificationStatus
        )
        if let idx = doctors.firstIndex(where: { $0.id == profile.id }) {
            doctors[idx] = summary
        } else {
            doctors.append(summary)
        }
        save()
    }

    /// Folds in the hospital's credentialed doctors from Supabase. Remote wins on
    /// name/verification; locally seeded demo doctors are left untouched.
    public func mergeRemote(_ remote: [DoctorSummary]) {
        guard !remote.isEmpty else { return }
        for doc in remote {
            if let idx = doctors.firstIndex(where: { $0.id == doc.id }) {
                doctors[idx] = doc
            } else {
                doctors.append(doc)
            }
        }
        save()
    }

    /// Repoints a roster entry held under a pre-Supabase doctor id. See `DoctorIdentity`.
    public func remapDoctor(from previous: UUID, to next: UUID) {
        guard let idx = doctors.firstIndex(where: { $0.id == previous }) else { return }
        let old = doctors[idx]
        doctors[idx] = DoctorSummary(
            id: next,
            name: old.name,
            credential: old.credential,
            specialty: old.specialty,
            npi: old.npi,
            isAutoApproved: old.isAutoApproved,
            verificationStatus: old.verificationStatus
        )
        save()
    }

    public func toggleAutoApprove(id: UUID) {
        guard let idx = doctors.firstIndex(where: { $0.id == id }) else { return }
        doctors[idx].isAutoApproved.toggle()
        save()
        if doctors[idx].isAutoApproved {
            TokenStore.shared.autoApprovePending(forDoctorID: id)
        }
        if let hospitalID = SessionStore.shared.currentHospitalID {
            let autoApprove = doctors[idx].isAutoApproved
            Task { await SupabaseRosterRepository.setAutoApprove(hospitalID: hospitalID, doctorID: id, autoApprove: autoApprove) }
        }
    }

    public func isAutoApproved(doctorID: UUID) -> Bool {
        doctors.first { $0.id == doctorID }?.isAutoApproved ?? false
    }

    public func eligibleTradePartners(for specialty: String, excluding doctorID: UUID) -> [DoctorSummary] {
        doctors.filter {
            $0.id != doctorID &&
            DoctorPreferencesStore.specialtyMatches($0.specialty, specialty) &&
            $0.verificationStatus == .verified
        }
    }

    // MARK: - Demo seed

    /// Injects a set of verified mock doctors (one per specialty used in demo shifts).
    /// Also ensures at least two partners exist for the current doctor's specialties.
    public func seedMockDoctorsIfNeeded() {
        let mockIDs: [UUID] = [
            UUID(uuidString: "E1000001-0000-0000-0000-000000000000")!,
            UUID(uuidString: "E2000001-0000-0000-0000-000000000000")!,
            UUID(uuidString: "E3000001-0000-0000-0000-000000000000")!,
            UUID(uuidString: "E4000001-0000-0000-0000-000000000000")!,
            UUID(uuidString: "E5000001-0000-0000-0000-000000000000")!,
            UUID(uuidString: "E6000001-0000-0000-0000-000000000000")!,
            UUID(uuidString: "E7000001-0000-0000-0000-000000000000")!,
        ]

        let mocks: [DoctorSummary] = [
            DoctorSummary(id: mockIDs[0], name: "Dr. James Carter",  credential: "MD", specialty: "Cardiology",         npi: "1932756480", isAutoApproved: true, verificationStatus: .verified),
            DoctorSummary(id: mockIDs[1], name: "Dr. Lisa Chen",     credential: "MD", specialty: "Cardiology",         npi: "1073648291", isAutoApproved: true, verificationStatus: .verified),
            DoctorSummary(id: mockIDs[2], name: "Dr. Maria Santos",  credential: "MD", specialty: "Emergency Medicine", npi: "1548372916", isAutoApproved: true, verificationStatus: .verified),
            DoctorSummary(id: mockIDs[3], name: "Dr. David Park",    credential: "DO", specialty: "Orthopedics",        npi: "1629384750", isAutoApproved: true, verificationStatus: .verified),
            DoctorSummary(id: mockIDs[4], name: "Dr. Sarah Kim",     credential: "MD", specialty: "General Surgery",    npi: "1807263549", isAutoApproved: true, verificationStatus: .verified),
            DoctorSummary(id: mockIDs[5], name: "Dr. Robert Nguyen", credential: "MD", specialty: "Internal Medicine",  npi: "1394827163", isAutoApproved: true, verificationStatus: .verified),
            DoctorSummary(id: mockIDs[6], name: "Dr. Emily Walsh",   credential: "MD", specialty: "Emergency Medicine", npi: "1265839407", isAutoApproved: true, verificationStatus: .verified),
        ]
        for doc in mocks where !doctors.contains(where: { $0.id == doc.id }) {
            doctors.append(doc)
        }

        // Guarantee trade partners for whatever specialty the logged-in doctor uses.
        let profileSpecialties = DoctorProfile.load()?.specialties ?? []
        let partnerNames = ["Dr. Alex Rivera", "Dr. Jordan Lee"]
        for (idx, specialty) in profileSpecialties.enumerated() {
            let matching = doctors.filter {
                DoctorPreferencesStore.specialtyMatches($0.specialty, specialty)
            }
            let needed = max(0, 2 - matching.count)
            guard needed > 0 else { continue }
            for n in 0..<needed {
                let name = partnerNames[(idx + n) % partnerNames.count]
                let id = UUID(uuidString: String(format: "E8%06X-0000-0000-0000-000000000000", (idx * 10 + n + 1) & 0xFFFFFF))!
                if doctors.contains(where: { $0.id == id }) { continue }
                doctors.append(DoctorSummary(
                    id: id,
                    name: name,
                    credential: "MD",
                    specialty: specialty,
                    npi: String(format: "1%09d", abs(id.hashValue) % 1_000_000_000),
                    isAutoApproved: true,
                    verificationStatus: .verified
                ))
            }
        }
        save()
    }

    /// Removes mock doctors added by seedMockDoctorsIfNeeded.
    public func clearMockDoctors() {
        let mockIDs: Set<UUID> = [
            UUID(uuidString: "E1000001-0000-0000-0000-000000000000")!,
            UUID(uuidString: "E2000001-0000-0000-0000-000000000000")!,
            UUID(uuidString: "E3000001-0000-0000-0000-000000000000")!,
            UUID(uuidString: "E4000001-0000-0000-0000-000000000000")!,
            UUID(uuidString: "E5000001-0000-0000-0000-000000000000")!,
            UUID(uuidString: "E6000001-0000-0000-0000-000000000000")!,
            UUID(uuidString: "E7000001-0000-0000-0000-000000000000")!,
        ]
        doctors.removeAll { mockIDs.contains($0.id) }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([DoctorSummary].self, from: data) else { return }
        doctors = stored
    }

    private func save() {
        if let data = try? JSONEncoder().encode(doctors) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

extension DoctorSummary: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, credential, specialty, npi, verificationStatus, isAutoApproved
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        credential = try c.decode(String.self, forKey: .credential)
        specialty = try c.decode(String.self, forKey: .specialty)
        npi = try c.decodeIfPresent(String.self, forKey: .npi) ?? ""
        verificationStatus = try c.decode(VerificationStatus.self, forKey: .verificationStatus)
        isAutoApproved = try c.decodeIfPresent(Bool.self, forKey: .isAutoApproved) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(credential, forKey: .credential)
        try c.encode(specialty, forKey: .specialty)
        try c.encode(npi, forKey: .npi)
        try c.encode(verificationStatus, forKey: .verificationStatus)
        try c.encode(isAutoApproved, forKey: .isAutoApproved)
    }
}
