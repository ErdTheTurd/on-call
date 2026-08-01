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

// MARK: - Local Implementations (Phase 0 default)

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

    func submit(_ request: TokenStore.TokenRequest) async throws {
        // TokenStore handles local submit via requestDay
    }

    func updateStatus(id: UUID, status: TokenStore.TokenRequest.RequestStatus) async throws {
        switch status {
        case .approved: TokenStore.shared.approve(id: id)
        case .denied: TokenStore.shared.deny(id: id)
        case .autoApproved: break
        case .pending: break
        }
    }
}

// MARK: - Supabase Implementations

@MainActor
final class SupabaseShiftRepository: ShiftRepositoryProtocol {
    static let shared = SupabaseShiftRepository()

    func fetchOpenShifts(hospitalID: UUID?) async throws -> [Shift] {
        guard SupabaseConfig.isConfigured else {
            return try await LocalShiftRepository.shared.fetchOpenShifts(hospitalID: hospitalID)
        }
        var path = "rest/v1/shifts?select=*"
        if let hospitalID { path += "&hospital_id=eq.\(hospitalID.uuidString)" }
        let data = try await SupabaseHTTPClient.shared.request(path: path, accessToken: SupabaseAuthService.shared.accessToken)
        let rows = try JSONDecoder().decode([SupabaseShiftRow].self, from: data)
        let shifts = rows.map { $0.toShift() }
        await MainActor.run {
            for shift in shifts { Services.hospital.upsertShift(shift) }
        }
        return shifts
    }

    func upsert(_ shift: Shift) async throws {
        Services.hospital.upsertShift(shift)
        guard SupabaseConfig.isConfigured else { return }
        let row = SupabaseShiftRow.from(shift)
        _ = try await SupabaseHTTPClient.shared.request(
            path: "rest/v1/shifts",
            method: "POST",
            body: try JSONEncoder().encode(row),
            accessToken: SupabaseAuthService.shared.accessToken
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

// MARK: - Sync Coordinator

@MainActor
final class DataSyncCoordinator: ObservableObject {
    static let shared = DataSyncCoordinator()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?

    private var timer: Timer?

    func startPeriodicSync() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { await self.syncAll() }
        }
    }

    func syncAll() async {
        guard SupabaseConfig.isConfigured else { return }
        isSyncing = true
        defer { isSyncing = false; lastSyncDate = Date() }
        _ = try? await SupabaseShiftRepository.shared.fetchOpenShifts(hospitalID: SessionStore.shared.currentHospitalID)
    }
}

enum Repositories {
    static var shifts: ShiftRepositoryProtocol {
        SupabaseConfig.isConfigured ? SupabaseShiftRepository.shared : LocalShiftRepository.shared
    }
    static var assignments: AssignmentRepositoryProtocol { LocalAssignmentRepository.shared }
    static var tokens: TokenRepositoryProtocol { LocalTokenRepository.shared }
}
