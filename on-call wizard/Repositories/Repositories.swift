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
            return TokenStore.shared.pendingRequests(forHospitalID: hospitalID)
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

private struct AnyJSON {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
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
        var path = "rest/v1/shifts?select=*&order=date.asc"
        if let hospitalID { path += "&hospital_id=eq.\(hospitalID.uuidString)" }
        let data = try await SupabaseHTTPClient.shared.request(path: path, accessToken: SupabaseAuthService.shared.accessToken)
        let rows = try AnyJSON.decoder.decode([SupabaseShiftRow].self, from: data)
        let shifts = rows.map { $0.toShift() }
        for shift in shifts { Services.hospital.upsertShift(shift) }
        return shifts
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
        var path = "rest/v1/assignments?select=*,shifts(*)"
        if let doctorID { path += "&doctor_id=eq.\(doctorID.uuidString)" }
        let data = try await SupabaseHTTPClient.shared.request(path: path, accessToken: SupabaseAuthService.shared.accessToken)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

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
               let date = ISO8601DateFormatter().date(from: dateStr) ?? ISO8601DateFormatter().date(from: dateStr + "Z") {
                shift = Shift(
                    id: shiftID,
                    hospitalID: hid,
                    hospital: embedded["hospital_name"] as? String ?? "Hospital",
                    specialty: embedded["specialty"] as? String ?? "Internal Medicine",
                    start: date,
                    durationHours: Int(embedded["duration_hours"] as? Double ?? 24),
                    rateFloor: embedded["rate_floor"] as? Double ?? 0,
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
        guard SupabaseConfig.isConfigured else {
            return try await LocalTokenRepository.shared.fetchRequests(hospitalID: hospitalID)
        }
        var path = "rest/v1/token_requests?select=*&order=requested_at.desc"
        if let hospitalID { path += "&hospital_id=eq.\(hospitalID.uuidString)" }
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
    static func upsertDoctor(_ profile: DoctorProfile) async {
        guard SupabaseConfig.isConfigured, let userID = profile.userID ?? SessionStore.shared.currentUserID else { return }
        let row: [String: Any] = [
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
        _ = try? await SupabaseHTTPClient.shared.request(
            path: "rest/v1/doctor_profiles?on_conflict=profile_id",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: row),
            accessToken: SupabaseAuthService.shared.accessToken,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    static func upsertHospital(_ profile: HospitalProfile) async {
        guard SupabaseConfig.isConfigured, let userID = profile.userID ?? SessionStore.shared.currentUserID else { return }
        let row: [String: Any] = [
            "id": profile.id.uuidString,
            "profile_id": userID.uuidString,
            "name": profile.name,
            "npi": profile.npi,
            "verification_status": profile.verificationStatus.rawValue,
            "email": profile.email,
            "verification_flags": profile.verificationFlags
        ]
        _ = try? await SupabaseHTTPClient.shared.request(
            path: "rest/v1/hospital_profiles?on_conflict=id",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: row),
            accessToken: SupabaseAuthService.shared.accessToken,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
        let policyRow: [String: Any] = [
            "hospital_id": profile.id.uuidString,
            "policy": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(profile.schedulingPolicy))) ?? [:]
        ]
        _ = try? await SupabaseHTTPClient.shared.request(
            path: "rest/v1/scheduling_policies?on_conflict=hospital_id",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: policyRow),
            accessToken: SupabaseAuthService.shared.accessToken,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
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
        isSyncing = true
        defer { isSyncing = false; lastSyncDate = Date() }

        do {
            _ = try await SupabaseShiftRepository.shared.fetchOpenShifts(hospitalID: SessionStore.shared.currentHospitalID)

            if let doctorID = SessionStore.shared.currentUserID ?? DoctorProfile.load()?.id {
                let remote = try await SupabaseAssignmentRepository.shared.fetchAssignments(doctorID: doctorID)
                if !remote.isEmpty {
                    // Merge remote into local store by replacing matching IDs
                    for item in remote {
                        if !AssignedShiftsStore.shared.assignedShifts.contains(where: { $0.id == item.id }) {
                            await AssignedShiftsStore.shared.assign(item.shift, doctorID: item.doctorID)
                        }
                    }
                }
            }

            if let hospitalID = SessionStore.shared.currentHospitalID {
                let tokens = try await SupabaseTokenRepository.shared.fetchRequests(hospitalID: hospitalID)
                TokenStore.shared.mergeRemote(tokens)
            } else {
                let tokens = try await SupabaseTokenRepository.shared.fetchRequests(hospitalID: nil)
                TokenStore.shared.mergeRemote(tokens)
            }

            if let doctor = DoctorProfile.load() {
                await SupabaseProfileSync.upsertDoctor(doctor)
            }
            if let hospital = HospitalProfile.load() {
                await SupabaseProfileSync.upsertHospital(hospital)
            }

            lastError = nil
        } catch {
            lastError = error.localizedDescription
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
