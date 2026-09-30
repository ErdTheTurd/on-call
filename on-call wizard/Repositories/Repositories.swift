import Foundation
import Combine

// MARK: - Repository Protocols

protocol ShiftRepositoryProtocol {
    func fetchOpenShifts(hospitalID: UUID?) async throws -> [Shift]
    func upsert(_ shift: Shift) async throws
}

protocol AssignmentRepositoryProtocol {
    func fetchAssignments(doctorID: UUID?) async throws -> [AssignedShiftsStore.AssignedShift]
    func assign(_ shift: Shift, doctorID: UUID) async throws
}

protocol TokenRepositoryProtocol {
    func fetchRequests(hospitalID: UUID?) async throws -> [TokenStore.TokenRequest]
    func submit(_ request: TokenStore.TokenRequest) async throws
    func updateStatus(id: UUID, status: TokenStore.TokenRequest.RequestStatus) async throws
}

// MARK: - Local Implementations

@MainActor
final class LocalShiftRepository: ShiftRepositoryProtocol {
    static let shared = LocalShiftRepository()

    func fetchOpenShifts(hospitalID: UUID?) async throws -> [Shift] {
        let all = Services.hospital.shifts
        if let hospitalID {
            return all.filter { $0.hospitalID == hospitalID && !$0.isPast }
        }
        return all.filter { !$0.isPast && !AssignedShiftsStore.shared.isShiftFilled($0.id) }
    }

    func upsert(_ shift: Shift) async throws {
        Services.hospital.upsertShift(shift)
    }
}

@MainActor
final class LocalAssignmentRepository: AssignmentRepositoryProtocol {
    static let shared = LocalAssignmentRepository()

    func fetchAssignments(doctorID: UUID?) async throws -> [AssignedShiftsStore.AssignedShift] {
        AssignedShiftsStore.shared.activeAssignedShifts(for: doctorID)
    }

    func assign(_ shift: Shift, doctorID: UUID) async throws {
        await AssignedShiftsStore.shared.assign(shift, doctorID: doctorID)
    }
}

@MainActor
final class LocalTokenRepository: TokenRepositoryProtocol {
    static let shared = LocalTokenRepository()

    func fetchRequests(hospitalID: UUID?) async throws -> [TokenStore.TokenRequest] {
        if let hospitalID {
            return TokenStore.shared.requests(forHospitalID: hospitalID)
        }
        return TokenStore.shared.requestedDays
    }

    func submit(_ request: TokenStore.TokenRequest) async throws {}

    func updateStatus(id: UUID, status: TokenStore.TokenRequest.RequestStatus) async throws {
        switch status {
        case .approved: TokenStore.shared.approve(id: id)
        case .denied: TokenStore.shared.deny(id: id)
        case .autoApproved, .pending: break
        }
    }
}

// MARK: - Shared JSON helpers

private func parseServerDate(_ raw: String) -> Date? {
    let frac = ISO8601DateFormatter()
    frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = frac.date(from: raw) { return date }
    let plain = ISO8601DateFormatter()
    if let date = plain.date(from: raw) { return date }
    let swapped = raw.replacingOccurrences(of: " ", with: "T")
    if let date = plain.date(from: swapped) { return date }
    return nil
}

private struct AnyJSON {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parseServerDate(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: raw)
        }
        return d
    }()
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private func isoDateOnly(_ date: Date) -> String {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: date)
}

// MARK: - Supabase Shift Repository

@MainActor
final class SupabaseShiftRepository: ShiftRepositoryProtocol {
    static let shared = SupabaseShiftRepository()

    func fetchOpenShifts(hospitalID: UUID?) async throws -> [Shift] {
        guard SupabaseConfig.isConfigured else {
            return try await LocalShiftRepository.shared.fetchOpenShifts(hospitalID: hospitalID)
        }
        var path = "rest/v1/shifts?select=*&order=date.asc&limit=2000"
        if let hospitalID { path += "&hospital_id=eq.\(hospitalID.uuidString)" }
        let data = try await SupabaseHTTPClient.shared.request(path: path, accessToken: SupabaseAuthService.shared.accessToken)
        let rows = try AnyJSON.decoder.decode([SupabaseShiftRow].self, from: data)
        return rows.map { $0.toShift() }
    }

    /// Shift ids that already have a non-canceled assignment. No doctor identity.
    func fetchFilledShiftIDs() async throws -> Set<UUID> {
        guard SupabaseConfig.isConfigured else { return [] }
        let data = try await SupabaseHTTPClient.shared.request(
            path: "rest/v1/shift_coverage?select=shift_id&is_filled=eq.true&limit=2000",
            accessToken: SupabaseAuthService.shared.accessToken
        )
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return Set(rows.compactMap { UUID(uuidString: $0["shift_id"] as? String ?? "") })
    }

    func upsert(_ shift: Shift) async throws {
        Services.hospital.upsertShift(shift)
        guard SupabaseConfig.isConfigured else { return }
        let row = SupabaseShiftRow.from(shift)
        var req = try JSONSerialization.jsonObject(with: AnyJSON.encoder.encode(row)) as? [String: Any] ?? [:]
        let body = try JSONSerialization.data(withJSONObject: req)
        _ = try await SupabaseHTTPClient.shared.request(
            path: "rest/v1/shifts?on_conflict=id",
            method: "POST",
            body: body,
            accessToken: SupabaseAuthService.shared.accessToken,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }
}

private struct SupabaseShiftRow: Codable {
    let id: UUID
    let hospital_id: UUID
    let hospital_name: String
    let specialty: String
    let date: Date
    let rate_floor: Double
    let rate_unit: String
    let duration_hours: Double

    func toShift() -> Shift {
        Shift(
            id: id,
            hospitalID: hospital_id,
            hospital: hospital_name,
            specialty: specialty,
            start: date,
            durationHours: Int(duration_hours),
            rateFloor: rate_floor,
            rateUnit: rate_unit == "per_hour" ? .perHour : .perDay
        )
    }

    static func from(_ shift: Shift) -> SupabaseShiftRow {
        SupabaseShiftRow(
            id: shift.id,
            hospital_id: shift.hospitalID,
            hospital_name: shift.hospital,
            specialty: shift.specialty,
            date: shift.date,
            rate_floor: shift.rateFloor,
            rate_unit: shift.rateUnit == .perHour ? "per_hour" : "per_day",
            duration_hours: Double(shift.durationHours)
        )
    }
}

// MARK: - Supabase Assignment Repository

@MainActor
final class SupabaseAssignmentRepository: AssignmentRepositoryProtocol {
    static let shared = SupabaseAssignmentRepository()

    func fetchAssignments(doctorID: UUID?) async throws -> [AssignedShiftsStore.AssignedShift] {
        guard SupabaseConfig.isConfigured else {
            return try await LocalAssignmentRepository.shared.fetchAssignments(doctorID: doctorID)
        }
        var path = "rest/v1/assignments?select=*,shifts(*)&limit=2000"
        if let doctorID { path += "&doctor_id=eq.\(doctorID.uuidString)" }
        let data = try await SupabaseHTTPClient.shared.request(path: path, accessToken: SupabaseAuthService.shared.accessToken)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return parseAssignmentRows(rows)
    }

    /// Every assignment on this hospital's shifts, including the other doctors' names' ids.
    func fetchHospitalAssignments(hospitalID: UUID) async throws -> [AssignedShiftsStore.AssignedShift] {
        guard SupabaseConfig.isConfigured else { return [] }
        let path = "rest/v1/assignments?select=*,shifts!inner(*)&shifts.hospital_id=eq.\(hospitalID.uuidString)&limit=2000"
        let data = try await SupabaseHTTPClient.shared.request(path: path, accessToken: SupabaseAuthService.shared.accessToken)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return parseAssignmentRows(rows)
    }

    private func parseAssignmentRows(_ rows: [[String: Any]]) -> [AssignedShiftsStore.AssignedShift] {
        var result: [AssignedShiftsStore.AssignedShift] = []
        for row in rows {
            guard
                let idStr = row["id"] as? String, let id = UUID(uuidString: idStr),
                let shiftIDStr = row["shift_id"] as? String, let shiftID = UUID(uuidString: shiftIDStr),
                let doctorIDStr = row["doctor_id"] as? String, let docID = UUID(uuidString: doctorIDStr),
                let statusRaw = row["status"] as? String
            else { continue }

            let status: DoctorShift.Status = {
                switch statusRaw {
                case "canceled": return .canceled
                case "traded_pending": return .tradedPending
                case "traded_complete": return .scheduled
                default: return .scheduled
                }
            }()

            var shift: Shift?
            if let embedded = row["shifts"] as? [String: Any],
               let hid = UUID(uuidString: embedded["hospital_id"] as? String ?? ""),
               let dateStr = embedded["date"] as? String,
               let date = parseServerDate(dateStr) ?? parseServerDate(dateStr + "Z") {
                shift = Shift(
                    id: shiftID,
                    hospitalID: hid,
                    hospital: embedded["hospital_name"] as? String ?? "Hospital",
                    specialty: embedded["specialty"] as? String ?? "Internal Medicine",
                    start: date,
                    durationHours: Int((embedded["duration_hours"] as? NSNumber)?.doubleValue ?? 24),
                    rateFloor: (embedded["rate_floor"] as? NSNumber)?.doubleValue ?? 0,
                    rateUnit: (embedded["rate_unit"] as? String) == "per_hour" ? .perHour : .perDay
                )
            } else {
                shift = Services.hospital.shifts.first { $0.id == shiftID }
            }
            guard let shift else { continue }
            result.append(.init(id: id, shift: shift, doctorID: docID, status: status))
        }
        return result
    }

    func assign(_ shift: Shift, doctorID: UUID) async throws {
        await AssignedShiftsStore.shared.assign(shift, doctorID: doctorID)
        guard SupabaseConfig.isConfigured else { return }
        do {
            _ = try await SupabaseHTTPClient.shared.invokeFunction(
                name: "accept-shift",
                body: [
                    "shift_id": shift.id.uuidString,
                    "doctor_id": doctorID.uuidString,
                    "hospital_id": shift.hospitalID.uuidString,
                    "shift_date": isoDateOnly(shift.date)
                ],
                accessToken: SupabaseAuthService.shared.accessToken
            )
        } catch {
            // Fallback to direct insert if edge function unavailable
            let row: [String: Any] = [
                "shift_id": shift.id.uuidString,
                "doctor_id": doctorID.uuidString,
                "status": "scheduled"
            ]
            _ = try await SupabaseHTTPClient.shared.request(
                path: "rest/v1/assignments",
                method: "POST",
                body: try JSONSerialization.data(withJSONObject: row),
                accessToken: SupabaseAuthService.shared.accessToken
            )
        }
    }
}

// MARK: - Supabase Token Repository

@MainActor
final class SupabaseTokenRepository: TokenRepositoryProtocol {
    static let shared = SupabaseTokenRepository()

    func fetchRequests(hospitalID: UUID?) async throws -> [TokenStore.TokenRequest] {
        try await fetchQueue(hospitalID: hospitalID, doctorID: nil)
    }

    /// Reads `token_request_queue` so the hospital sees the doctor's display name.
    /// Falls back to `token_requests` when that view is not deployed yet.
    func fetchQueue(hospitalID: UUID?, doctorID: UUID?) async throws -> [TokenStore.TokenRequest] {
        guard SupabaseConfig.isConfigured else {
            return try await LocalTokenRepository.shared.fetchRequests(hospitalID: hospitalID)
        }
        do {
            return try await fetchTokenRows(table: "token_request_queue", hospitalID: hospitalID, doctorID: doctorID)
        } catch {
            return try await fetchTokenRows(table: "token_requests", hospitalID: hospitalID, doctorID: doctorID)
        }
    }

    private func fetchTokenRows(table: String, hospitalID: UUID?, doctorID: UUID?) async throws -> [TokenStore.TokenRequest] {
        var path = "rest/v1/\(table)?select=*&order=requested_at.desc&limit=500"
        if let hospitalID { path += "&hospital_id=eq.\(hospitalID.uuidString)" }
        if let doctorID { path += "&doctor_id=eq.\(doctorID.uuidString)" }
        let data = try await SupabaseHTTPClient.shared.request(path: path, accessToken: SupabaseAuthService.shared.accessToken)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.compactMap { row -> TokenStore.TokenRequest? in
            guard
                let id = UUID(uuidString: row["id"] as? String ?? ""),
                let doctorID = UUID(uuidString: row["doctor_id"] as? String ?? ""),
                let hospitalID = UUID(uuidString: row["hospital_id"] as? String ?? ""),
                let specialty = row["specialty"] as? String,
                let statusRaw = row["status"] as? String,
                let status = TokenStore.TokenRequest.RequestStatus(rawValue: statusRaw)
            else { return nil }
            let dateStr = row["shift_date"] as? String ?? ""
            let date = ISO8601DateFormatter().date(from: dateStr)
                ?? DateFormatter.yyyyMMdd.date(from: dateStr)
                ?? Date()
            let requestedAt = ISO8601DateFormatter().date(from: row["requested_at"] as? String ?? "") ?? Date()
            return TokenStore.TokenRequest(
                id: id,
                doctorID: doctorID,
                doctorName: row["doctor_name"] as? String ?? "Doctor",
                credential: row["credential"] as? String ?? "MD",
                hospitalID: hospitalID,
                date: date,
                status: status,
                hospitalName: row["hospital_name"] as? String ?? "Hospital",
                specialty: specialty,
                requestedAt: requestedAt,
                approvedAt: nil,
                shiftRate: row["shift_rate"] as? Double
            )
        }
    }

    func submit(_ request: TokenStore.TokenRequest) async throws {
        guard SupabaseConfig.isConfigured else { return }
        let row: [String: Any] = [
            "id": request.id.uuidString,
            "doctor_id": request.doctorID.uuidString,
            "hospital_id": request.hospitalID.uuidString,
            "shift_date": isoDateOnly(request.date),
            "status": request.status.rawValue,
            "specialty": request.specialty
        ]
        _ = try await SupabaseHTTPClient.shared.request(
            path: "rest/v1/token_requests",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: row),
            accessToken: SupabaseAuthService.shared.accessToken,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    func updateStatus(id: UUID, status: TokenStore.TokenRequest.RequestStatus) async throws {
        try await LocalTokenRepository.shared.updateStatus(id: id, status: status)
        guard SupabaseConfig.isConfigured else { return }
        let body = try JSONSerialization.data(withJSONObject: ["status": status.rawValue])
        _ = try await SupabaseHTTPClient.shared.request(
            path: "rest/v1/token_requests?id=eq.\(id.uuidString)",
            method: "PATCH",
            body: body,
            accessToken: SupabaseAuthService.shared.accessToken,
            prefer: "return=minimal"
        )
    }
}

private extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Profile Sync

@MainActor
enum SupabaseProfileSync {
    /// Loads the signed-in user's server profile and stores it on this device.
    /// Returns nil when the row is missing or onboarding is unfinished.
    /// Throws on a network or server error so a same-user local profile can be kept.
    static func hydrate(preferredRole: UserRole, email: String) async throws -> UserRole? {
        guard SupabaseConfig.isConfigured,
              let token = SupabaseAuthService.shared.accessToken,
              let userID = SupabaseAuthService.shared.currentUserID else { return nil }

        let role = try await fetchServerRole(userID: userID, token: token) ?? preferredRole
        switch role {
        case .doctor:
            guard let profile = try await fetchDoctor(userID: userID, email: email, token: token) else { return nil }
            profile.save()
            UserDefaults.standard.removeObject(forKey: HospitalProfile.storageKey)
            guard profile.isOnboardingComplete else { return nil }
            markPushed(kind: "doctor", id: userID, payload: doctorRow(profile, userID: userID))
            return .doctor
        case .hospital:
            guard let profile = try await fetchHospital(userID: userID, email: email, token: token) else { return nil }
            profile.save()
            SchedulingPolicyStore.shared.setPolicy(profile.schedulingPolicy, for: profile.id)
            UserDefaults.standard.removeObject(forKey: DoctorProfile.storageKey)
            guard profile.isOnboardingComplete else { return nil }
            markPushed(kind: "hospital", id: profile.id, payload: hospitalFingerprint(profile, userID: userID))
            return .hospital
        }
    }

    static func upsertDoctor(_ profile: DoctorProfile) async {
        guard SupabaseConfig.isConfigured, profile.isOnboardingComplete,
              let userID = profile.userID ?? SessionStore.shared.currentUserID else { return }
        let row = doctorRow(profile, userID: userID)
        guard needsPush(kind: "doctor", id: userID, payload: row) else { return }
        do {
            _ = try await SupabaseHTTPClient.shared.request(
                path: "rest/v1/doctor_profiles?on_conflict=profile_id",
                method: "POST",
                body: try JSONSerialization.data(withJSONObject: row),
                accessToken: SupabaseAuthService.shared.accessToken,
                prefer: "resolution=merge-duplicates,return=minimal"
            )
            markPushed(kind: "doctor", id: userID, payload: row)
        } catch {
            return
        }
    }

    static func upsertHospital(_ profile: HospitalProfile) async throws {
        guard SupabaseConfig.isConfigured, profile.isOnboardingComplete,
              let userID = profile.userID ?? SessionStore.shared.currentUserID else { return }
        let fingerprint = hospitalFingerprint(profile, userID: userID)
        guard needsPush(kind: "hospital", id: profile.id, payload: fingerprint) else { return }
        let row = hospitalRow(profile, userID: userID)
        _ = try await SupabaseHTTPClient.shared.request(
            path: "rest/v1/hospital_profiles?on_conflict=id",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: row),
            accessToken: SupabaseAuthService.shared.accessToken,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
        let policyObject = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(profile.schedulingPolicy))) ?? [:]
        let policyRow: [String: Any] = [
            "hospital_id": profile.id.uuidString,
            "policy": policyObject
        ]
        _ = try await SupabaseHTTPClient.shared.request(
            path: "rest/v1/scheduling_policies?on_conflict=hospital_id",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: policyRow),
            accessToken: SupabaseAuthService.shared.accessToken,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
        markPushed(kind: "hospital", id: profile.id, payload: fingerprint)
    }

    private static func fetchServerRole(userID: UUID, token: String) async throws -> UserRole? {
        let profileRows = try await Self.rows(path: "rest/v1/profiles?id=eq.\(userID.uuidString)&select=role", token: token)
        guard let raw = profileRows.first?["role"] as? String else { return nil }
        switch raw.lowercased() {
        case "hospital": return .hospital
        case "doctor": return .doctor
        default: return nil
        }
    }

    private static func fetchDoctor(userID: UUID, email: String, token: String) async throws -> DoctorProfile? {
        let profileRows = try await Self.rows(path: "rest/v1/doctor_profiles?profile_id=eq.\(userID.uuidString)&select=*", token: token)
        guard let row = profileRows.first else { return nil }
        let credential = DoctorProfile.CredentialType(rawValue: row["credential"] as? String ?? "") ?? .md
        let status = VerificationStatus(rawValue: row["verification_status"] as? String ?? "") ?? .pending
        return DoctorProfile(
            id: userID,
            userID: userID,
            firstName: row["first_name"] as? String ?? "",
            lastName: row["last_name"] as? String ?? "",
            credential: credential,
            npi: row["npi"] as? String ?? "",
            deaNumber: row["dea_number"] as? String ?? "",
            licenseNumber: row["license_number"] as? String ?? "",
            licenseState: row["license_state"] as? String ?? "",
            specialties: row["specialties"] as? [String] ?? [],
            email: (row["email"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? email,
            verificationStatus: status,
            verificationFlags: row["verification_flags"] as? [String] ?? [],
            npiRegistryName: row["npi_registry_name"] as? String,
            npiTaxonomy: row["npi_taxonomy"] as? String
        )
    }

    private static func fetchHospital(userID: UUID, email: String, token: String) async throws -> HospitalProfile? {
        let profileRows = try await Self.rows(path: "rest/v1/hospital_profiles?profile_id=eq.\(userID.uuidString)&select=*", token: token)
        guard let row = profileRows.first, let id = UUID(uuidString: row["id"] as? String ?? "") else { return nil }
        let status = VerificationStatus(rawValue: row["verification_status"] as? String ?? "") ?? .pending
        var policy = SchedulingPolicy()
        let policyRows = try await Self.rows(
            path: "rest/v1/scheduling_policies?hospital_id=eq.\(id.uuidString)&select=policy",
            token: token
        )
        if let raw = policyRows.first?["policy"] {
            policy = decodePolicy(raw)
        }
        return HospitalProfile(
            id: id,
            userID: userID,
            name: row["name"] as? String ?? "",
            npi: row["npi"] as? String ?? "",
            email: (row["email"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? email,
            verificationStatus: status,
            verificationFlags: row["verification_flags"] as? [String] ?? [],
            npiRegistryName: row["npi_registry_name"] as? String,
            schedulingPolicy: policy
        )
    }

    private static func doctorRow(_ profile: DoctorProfile, userID: UUID) -> [String: Any] {
        [
            "profile_id": userID.uuidString,
            "first_name": profile.firstName,
            "last_name": profile.lastName,
            "credential": profile.credential.rawValue,
            "npi": profile.npi,
            "specialties": profile.specialties,
            "verification_status": profile.verificationStatus.rawValue,
            "dea_number": profile.deaNumber,
            "license_number": profile.licenseNumber,
            "license_state": profile.licenseState,
            "email": profile.email,
            "verification_flags": profile.verificationFlags
        ]
    }

    private static func hospitalRow(_ profile: HospitalProfile, userID: UUID) -> [String: Any] {
        [
            "id": profile.id.uuidString,
            "profile_id": userID.uuidString,
            "name": profile.name,
            "npi": profile.npi,
            "verification_status": profile.verificationStatus.rawValue,
            "email": profile.email,
            "verification_flags": profile.verificationFlags
        ]
    }

    private static func hospitalFingerprint(_ profile: HospitalProfile, userID: UUID) -> [String: Any] {
        var payload = hospitalRow(profile, userID: userID)
        payload["policy"] = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(profile.schedulingPolicy))) ?? [:]
        return payload
    }

    private static func decodePolicy(_ value: Any) -> SchedulingPolicy {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let policy = try? JSONDecoder().decode(SchedulingPolicy.self, from: data) else {
            return SchedulingPolicy()
        }
        return policy
    }

    private static func rows(path: String, token: String) async throws -> [[String: Any]] {
        let data = try await SupabaseHTTPClient.shared.request(path: path, accessToken: token)
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private static func fingerprintKey(kind: String, id: UUID) -> String {
        "profile_push_fp_\(kind)_\(id.uuidString)"
    }

    private static func canonical(_ payload: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    private static func needsPush(kind: String, id: UUID, payload: [String: Any]) -> Bool {
        let next = canonical(payload)
        guard !next.isEmpty else { return true }
        return UserDefaults.standard.string(forKey: fingerprintKey(kind: kind, id: id)) != next
    }

    private static func markPushed(kind: String, id: UUID, payload: [String: Any]) {
        let next = canonical(payload)
        guard !next.isEmpty else { return }
        UserDefaults.standard.set(next, forKey: fingerprintKey(kind: kind, id: id))
    }
}

// MARK: - Sync Coordinator

@MainActor
final class DataSyncCoordinator: ObservableObject {
    static let shared = DataSyncCoordinator()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var lastError: String?

    private var timer: Timer?

    func startPeriodicSync() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            Task { await self.syncAll() }
        }
        Task { await syncAll() }
    }

    func syncAll() async {
        guard SupabaseConfig.isConfigured else { return }
        // Explore and signed-out sessions keep their local sample data.
        guard SupabaseAuthService.shared.accessToken != nil else { return }
        isSyncing = true
        defer { isSyncing = false; lastSyncDate = Date() }

        let role = SessionStore.shared.currentRole
        do {
            let hospitalScope = role == .hospital ? SessionStore.shared.currentHospitalID : nil
            let shifts = try await SupabaseShiftRepository.shared.fetchOpenShifts(hospitalID: hospitalScope)
            Services.hospital.replaceAll(shifts)

            if role == .hospital, let hospitalID = SessionStore.shared.currentHospitalID {
                let assignments = try await SupabaseAssignmentRepository.shared.fetchHospitalAssignments(hospitalID: hospitalID)
                AssignedShiftsStore.shared.replaceAll(assignments)
                if let roster = await SupabaseRosterRepository.fetchForReplace(hospitalID: hospitalID) {
                    DoctorRosterStore.shared.replaceAll(roster)
                }
                let tokens = try await SupabaseTokenRepository.shared.fetchQueue(hospitalID: hospitalID, doctorID: nil)
                TokenStore.shared.replaceRemote(tokens)
                if let dates = try? await Self.fetchUnavailableDates(hospitalID: hospitalID) {
                    UnavailableDaysStore.shared.replace(hospitalID: hospitalID, dates: dates)
                }
                if let penalties = try? await Self.fetchPenalties(hospitalID: hospitalID, doctorID: nil) {
                    PenaltyLedgerStore.shared.replaceAll(penalties)
                }
                await SavingsReporter.shared.refresh(hospitalID: hospitalID)
                if let hospital = HospitalProfile.load() {
                    try await SupabaseProfileSync.upsertHospital(hospital)
                }
            } else if role == .doctor {
                let doctorID = SessionStore.shared.currentUserID ?? SessionStore.shared.currentDoctorID
                let mine = try await SupabaseAssignmentRepository.shared.fetchAssignments(doctorID: doctorID)
                AssignedShiftsStore.shared.replaceAll(mine)
                if let filled = try? await SupabaseShiftRepository.shared.fetchFilledShiftIDs() {
                    AssignedShiftsStore.shared.markFilledByOthers(shiftIDs: filled, knownShifts: shifts)
                }
                if let roster = await SupabaseRosterRepository.fetchVisible() {
                    DoctorRosterStore.shared.replaceAll(roster)
                }
                if let trades = await SupabaseTradeRepository.shared.fetch(doctorID: doctorID) {
                    ShiftTradeService.shared.replaceTrades(trades)
                    AssignedShiftsStore.shared.refreshTrades()
                }
                let tokens = try await SupabaseTokenRepository.shared.fetchQueue(hospitalID: nil, doctorID: doctorID)
                TokenStore.shared.replaceRemote(tokens)
                if let penalties = try? await Self.fetchPenalties(hospitalID: nil, doctorID: doctorID) {
                    PenaltyLedgerStore.shared.replaceAll(penalties)
                }
                if let doctor = DoctorProfile.load() {
                    await SupabaseProfileSync.upsertDoctor(doctor)
                }
            }

            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private static func fetchUnavailableDates(hospitalID: UUID) async throws -> [Date] {
        let data = try await SupabaseHTTPClient.shared.request(
            path: "rest/v1/unavailable_days?hospital_id=eq.\(hospitalID.uuidString)&select=date",
            accessToken: SupabaseAuthService.shared.accessToken
        )
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return rows.compactMap { row in
            guard let raw = row["date"] as? String else { return nil }
            return formatter.date(from: String(raw.prefix(10)))
        }
    }

    private static func fetchPenalties(hospitalID: UUID?, doctorID: UUID?) async throws -> [PenaltyLedgerStore.Entry] {
        var path = "rest/v1/penalty_ledger?select=*&order=created_at.desc&limit=500"
        if let hospitalID { path += "&hospital_id=eq.\(hospitalID.uuidString)" }
        if let doctorID { path += "&doctor_id=eq.\(doctorID.uuidString)" }
        let data = try await SupabaseHTTPClient.shared.request(
            path: path,
            accessToken: SupabaseAuthService.shared.accessToken
        )
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard
                let id = UUID(uuidString: row["id"] as? String ?? ""),
                let doctor = UUID(uuidString: row["doctor_id"] as? String ?? ""),
                let hospital = UUID(uuidString: row["hospital_id"] as? String ?? ""),
                let shift = UUID(uuidString: row["shift_id"] as? String ?? ""),
                let type = PenaltyLedgerStore.EntryType(rawValue: row["type"] as? String ?? "")
            else { return nil }
            let amount = (row["amount"] as? NSNumber)?.decimalValue
                ?? Decimal(string: row["amount"] as? String ?? "")
                ?? 0
            let createdRaw = row["created_at"] as? String ?? ""
            let created = parseServerDate(createdRaw) ?? Date()
            return PenaltyLedgerStore.Entry(
                id: id,
                doctorID: doctor,
                hospitalID: hospital,
                shiftID: shift,
                type: type,
                amount: amount,
                createdAt: created
            )
        }
    }
}

// MARK: - Hospital roster (Supabase)

enum SupabaseRosterRepository {
    static func link(hospitalID: UUID, doctorID: UUID) async {
        guard SupabaseConfig.isConfigured else { return }
        let row: [String: Any] = [
            "hospital_id": hospitalID.uuidString,
            "doctor_id": doctorID.uuidString,
            "auto_approve": false
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: row) else { return }
        _ = try? await SupabaseHTTPClient.shared.request(
            path: "rest/v1/hospital_doctors",
            method: "POST",
            body: body,
            accessToken: SupabaseAuthService.shared.accessToken,
            prefer: "resolution=ignore-duplicates,return=minimal"
        )
    }

    static func fetch(hospitalID: UUID) async -> [DoctorSummary] {
        await fetchRoster(hospitalID: hospitalID) ?? []
    }

    /// Approved peers visible to the signed-in doctor. The view already hides other hospitals.
    /// Nil means the request failed; an empty list means the server has nobody.
    static func fetchVisible() async -> [DoctorSummary]? {
        await fetchRoster(hospitalID: nil)
    }

    static func fetchForReplace(hospitalID: UUID) async -> [DoctorSummary]? {
        await fetchRoster(hospitalID: hospitalID)
    }

    private static func fetchRoster(hospitalID: UUID?) async -> [DoctorSummary]? {
        guard SupabaseConfig.isConfigured else { return [] }
        var path = "rest/v1/hospital_roster?select=doctor_id,auto_approve,first_name,last_name,credential,specialties,verification_status&limit=500"
        if let hospitalID { path += "&hospital_id=eq.\(hospitalID.uuidString)" }
        guard
            let data = try? await SupabaseHTTPClient.shared.request(
                path: path,
                accessToken: SupabaseAuthService.shared.accessToken
            ),
            let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }

        return rows.compactMap { row -> DoctorSummary? in
            guard let id = UUID(uuidString: row["doctor_id"] as? String ?? "") else { return nil }
            let first = row["first_name"] as? String ?? ""
            let last = row["last_name"] as? String ?? ""
            let specialties = row["specialties"] as? [String] ?? []
            let statusRaw = row["verification_status"] as? String ?? "unverified"
            return DoctorSummary(
                id: id,
                name: "\(first) \(last)".trimmingCharacters(in: .whitespaces),
                credential: row["credential"] as? String ?? "MD",
                specialty: specialties.first ?? "Internal Medicine",
                npi: "",
                isAutoApproved: row["auto_approve"] as? Bool ?? false,
                verificationStatus: VerificationStatus(rawValue: statusRaw) ?? .unverified
            )
        }
    }

    static func setAutoApprove(hospitalID: UUID, doctorID: UUID, autoApprove: Bool) async {
        guard SupabaseConfig.isConfigured else { return }
        guard let body = try? JSONSerialization.data(withJSONObject: ["auto_approve": autoApprove]) else { return }
        _ = try? await SupabaseHTTPClient.shared.request(
            path: "rest/v1/hospital_doctors?hospital_id=eq.\(hospitalID.uuidString)&doctor_id=eq.\(doctorID.uuidString)",
            method: "PATCH",
            body: body,
            accessToken: SupabaseAuthService.shared.accessToken,
            prefer: "return=minimal"
        )
    }
}

// MARK: - Trade sync (Supabase)

/// Shared `trade_requests` table + edge functions so partners see trades across devices.
@MainActor
final class SupabaseTradeRepository {
    static let shared = SupabaseTradeRepository()

    private static let iso = ISO8601DateFormatter()

    func push(_ trade: ShiftTradeRequest) async {
        guard SupabaseConfig.isConfigured else { return }
        var body: [String: Any] = [
            "id": trade.id.uuidString,
            "shift_id": trade.shiftID.uuidString,
            "from_doctor_id": trade.fromDoctorID.uuidString,
            "to_doctor_id": trade.toDoctorID.uuidString,
            "compensation_amount": trade.compensationAmount
        ]
        if let requested = trade.requestedShiftID { body["requested_shift_id"] = requested.uuidString }
        if let counter = trade.counterOfTradeID { body["counter_of_trade_id"] = counter.uuidString }
        if let name = trade.fromDoctorName { body["from_doctor_name"] = name }
        if let name = trade.toDoctorName { body["to_doctor_name"] = name }
        if let date = trade.offeredDate { body["offered_date"] = Self.iso.string(from: date) }
        if let date = trade.requestedDate { body["requested_date"] = Self.iso.string(from: date) }
        if let specialty = trade.specialty { body["specialty"] = specialty }

        _ = try? await SupabaseHTTPClient.shared.invokeFunction(
            name: "request-trade",
            body: body,
            accessToken: SupabaseAuthService.shared.accessToken
        )
    }

    func respond(tradeID: UUID, accept: Bool) async {
        guard SupabaseConfig.isConfigured else { return }
        _ = try? await SupabaseHTTPClient.shared.invokeFunction(
            name: "respond-trade",
            body: ["trade_id": tradeID.uuidString, "accept": accept],
            accessToken: SupabaseAuthService.shared.accessToken
        )
    }

    func fetch(doctorID: UUID) async -> [ShiftTradeRequest]? {
        guard SupabaseConfig.isConfigured else { return [] }
        let filter = "or=(from_doctor_id.eq.\(doctorID.uuidString),to_doctor_id.eq.\(doctorID.uuidString))"
        guard let data = try? await SupabaseHTTPClient.shared.request(
            path: "rest/v1/trade_requests?select=*&\(filter)&order=created_at.desc&limit=200",
            accessToken: SupabaseAuthService.shared.accessToken
        ), let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }

        return rows.compactMap { row in
            guard
                let id = UUID(uuidString: row["id"] as? String ?? ""),
                let shiftID = UUID(uuidString: row["shift_id"] as? String ?? ""),
                let from = UUID(uuidString: row["from_doctor_id"] as? String ?? ""),
                let to = UUID(uuidString: row["to_doctor_id"] as? String ?? "")
            else { return nil }

            let state = ShiftTradeRequest.State(rawValue: row["state"] as? String ?? "pending") ?? .pending
            let date = { (key: String) -> Date? in
                guard let raw = row[key] as? String else { return nil }
                return Self.iso.date(from: raw) ?? Self.iso.date(from: raw + "Z")
            }

            return ShiftTradeRequest(
                id: id,
                fromDoctorID: from,
                toDoctorID: to,
                shiftID: shiftID,
                requestedShiftID: UUID(uuidString: row["requested_shift_id"] as? String ?? ""),
                compensationAmount: (row["compensation_amount"] as? NSNumber)?.doubleValue
                    ?? Double(row["compensation_amount"] as? String ?? "")
                    ?? 0,
                counterOfTradeID: UUID(uuidString: row["counter_of_trade_id"] as? String ?? ""),
                createdAt: date("created_at") ?? Date(),
                state: state,
                fromDoctorName: row["from_doctor_name"] as? String,
                toDoctorName: row["to_doctor_name"] as? String,
                offeredDate: date("offered_date"),
                requestedDate: date("requested_date"),
                specialty: row["specialty"] as? String
            )
        }
    }
}

enum Repositories {
    static var shifts: ShiftRepositoryProtocol {
        SupabaseConfig.isConfigured ? SupabaseShiftRepository.shared : LocalShiftRepository.shared
    }
    static var assignments: AssignmentRepositoryProtocol {
        SupabaseConfig.isConfigured ? SupabaseAssignmentRepository.shared : LocalAssignmentRepository.shared
    }
    static var tokens: TokenRepositoryProtocol {
        SupabaseConfig.isConfigured ? SupabaseTokenRepository.shared : LocalTokenRepository.shared
    }
}
