import Foundation
import Combine
import SwiftUI

// MARK: - Assigned Shifts Store (doctor-facing)

@MainActor
public final class AssignedShiftsStore: ObservableObject {
    public static let shared = AssignedShiftsStore()

    @Published public private(set) var assignedShifts: [AssignedShift] = []
    @Published public private(set) var incomingTrades: [ShiftTradeRequest] = []
    @Published public private(set) var outgoingTrades: [ShiftTradeRequest] = []
    @Published public var lastError: String?

    public var currentDoctorID: UUID { SessionStore.shared.currentDoctorID }

    private let storageKey = "assigned_shifts_v1"
    private let tradeService = ShiftTradeService.shared

    public struct AssignedShift: Identifiable, Codable, Equatable {
        public let id: UUID
        public var shift: Shift
        public var doctorID: UUID
        public var status: DoctorShift.Status
        public let assignedAt: Date

        public init(id: UUID = UUID(), shift: Shift, doctorID: UUID, status: DoctorShift.Status = .scheduled, assignedAt: Date = Date()) {
            self.id = id
            self.shift = shift
            self.doctorID = doctorID
            self.status = status
            self.assignedAt = assignedAt
        }
    }

    private struct Stored: Codable {
        var shifts: [AssignedShift]
    }

    public init() {
        load()
        Task { await syncFromService() }
    }

    public func assign(_ shift: Shift, doctorID: UUID? = nil) async {
        let docID = doctorID ?? currentDoctorID
        let assigned = AssignedShift(shift: shift, doctorID: docID)
        assignedShifts.append(assigned)
        save()
        await tradeService.upsertShift(shift.toDoctorShift(doctorID: docID))
        let policy = SchedulingPolicyStore.shared.policy(for: shift.hospitalID)
        await tradeService.upsertPolicy(policy, for: shift.hospitalID)
    }

    public func cancelShift(_ assigned: AssignedShift) async throws -> Decimal {
        lastError = nil
        let policy = SchedulingPolicyStore.shared.policy(for: assigned.shift.hospitalID)
        let start = effectiveStart(for: assigned.shift, policy: policy)
        let preview = PenaltyCalculator.preview(for: .cancel, policy: policy, shiftStart: start, baseAmountOverride: Decimal(assigned.shift.totalEarnings))
        guard preview.allowed else { throw TradeError.cancelWindowClosed }

        let penalty = try await tradeService.cancelShift(shiftID: assigned.shift.id, by: assigned.doctorID)
        if let idx = assignedShifts.firstIndex(where: { $0.id == assigned.id }) {
            assignedShifts[idx].status = .canceled
        }
        save()
        PenaltyLedgerStore.shared.record(
            doctorID: assigned.doctorID,
            hospitalID: assigned.shift.hospitalID,
            shiftID: assigned.shift.id,
            type: .cancel,
            amount: penalty
        )
        return penalty
    }

    public func requestTrade(for assigned: AssignedShift, toDoctor: DoctorSummary) async throws -> ShiftTradeRequest {
        lastError = nil
        let trade = try await tradeService.requestTrade(
            shiftID: assigned.shift.id,
            fromDoctorID: assigned.doctorID,
            toDoctorID: toDoctor.id
        )
        if let idx = assignedShifts.firstIndex(where: { $0.id == assigned.id }) {
            assignedShifts[idx].status = .tradedPending
        }
        save()
        await syncFromService()
        return trade
    }

    public func respondToTrade(_ trade: ShiftTradeRequest, accept: Bool) async throws -> Decimal {
        lastError = nil
        let penalty = try await tradeService.respondToTrade(tradeID: trade.id, accept: accept)
        await syncFromService()
        if accept, let idx = assignedShifts.firstIndex(where: { $0.shift.id == trade.shiftID }) {
            assignedShifts[idx].doctorID = trade.toDoctorID
            assignedShifts[idx].status = .scheduled
        } else if !accept, let idx = assignedShifts.firstIndex(where: { $0.shift.id == trade.shiftID }) {
            assignedShifts[idx].status = .scheduled
        }
        if accept, penalty > 0, let assigned = assignedShifts.first(where: { $0.shift.id == trade.shiftID }) {
            PenaltyLedgerStore.shared.record(
                doctorID: trade.fromDoctorID,
                hospitalID: assigned.shift.hospitalID,
                shiftID: trade.shiftID,
                type: .trade,
                amount: penalty
            )
        }
        save()
        return penalty
    }

    public func preview(for action: SchedulingAction, assigned: AssignedShift) -> PolicyPreview {
        let policy = SchedulingPolicyStore.shared.policy(for: assigned.shift.hospitalID)
        let start = effectiveStart(for: assigned.shift, policy: policy)
        return PenaltyCalculator.preview(
            for: action,
            policy: policy,
            shiftStart: start,
            baseAmountOverride: Decimal(assigned.shift.totalEarnings)
        )
    }

    public func eligibleTradePartners(for assigned: AssignedShift) -> [DoctorSummary] {
        DoctorRosterStore.shared.eligibleTradePartners(
            for: assigned.shift.specialty,
            excluding: assigned.doctorID
        )
    }

    public func activeAssignedShifts(for doctorID: UUID? = nil) -> [AssignedShift] {
        let id = doctorID ?? currentDoctorID
        return assignedShifts.filter { $0.doctorID == id && $0.status != .canceled && !$0.shift.isPast }
    }

    public func completedShifts(for doctorID: UUID? = nil) -> [AssignedShift] {
        let id = doctorID ?? currentDoctorID
        return assignedShifts.filter { $0.doctorID == id && $0.status != .canceled && $0.shift.isPast }
    }

    public func totalEarnings(for doctorID: UUID? = nil) -> Double {
        activeAssignedShifts(for: doctorID).map(\.shift.totalEarnings).reduce(0, +)
            + completedShifts(for: doctorID).map(\.shift.totalEarnings).reduce(0, +)
    }

    public func assignedDoctorID(for shiftID: UUID) -> UUID? {
        assignedShifts.first { $0.shift.id == shiftID && $0.status != .canceled }?.doctorID
    }

    public func isShiftFilled(_ shiftID: UUID) -> Bool {
        assignedDoctorID(for: shiftID) != nil
    }

    public func hasPendingTrade(for shiftID: UUID) -> Bool {
        let incoming = incomingTrades.contains { $0.shiftID == shiftID && $0.state == .pending }
        let outgoing = outgoingTrades.contains { $0.shiftID == shiftID && $0.state == .pending }
        return incoming || outgoing
    }

    public func isFilledByOthers(on date: Date, shifts: [Shift], currentDoctorID: UUID) -> Bool {
        let cal = Calendar.current
        let dayShifts = shifts.filter { cal.isDate($0.date, inSameDayAs: date) && !$0.isPast }
        guard !dayShifts.isEmpty else { return false }

        let iHaveDay = assignedShifts.contains {
            cal.isDate($0.shift.date, inSameDayAs: date) &&
            $0.doctorID == currentDoctorID &&
            $0.status != .canceled
        }
        if iHaveDay { return false }

        return dayShifts.allSatisfy { shift in
            guard let doc = assignedDoctorID(for: shift.id) else { return false }
            return doc != currentDoctorID
        }
    }

    private func effectiveStart(for shift: Shift, policy: SchedulingPolicy) -> Date {
        if shift.rateUnit == .perHour { return shift.start }
        return Calendar.current.startOfDay(for: shift.date)
    }

    private func syncFromService() async {
        incomingTrades = await tradeService.pendingTrades(for: currentDoctorID, direction: .incoming)
        outgoingTrades = await tradeService.pendingTrades(for: currentDoctorID, direction: .outgoing)
    }

    // MARK: - Demo seed

    private static let mockShiftIDs: Set<UUID> = [
        UUID(uuidString: "D1000001-0000-0000-0000-000000000000")!,
        UUID(uuidString: "D2000001-0000-0000-0000-000000000000")!,
        UUID(uuidString: "D3000001-0000-0000-0000-000000000000")!,
        UUID(uuidString: "D4000001-0000-0000-0000-000000000000")!,
        UUID(uuidString: "D5000001-0000-0000-0000-000000000000")!,
        UUID(uuidString: "D6000001-0000-0000-0000-000000000000")!,
    ]

    /// Seeds two mock incoming trade offers so the accept/deny UI is visible.
    /// No-ops if incoming trades already exist.
    public func seedMockIncomingTradesIfNeeded() {
        guard incomingTrades.isEmpty else { return }
        incomingTrades = [
            ShiftTradeRequest(
                id: UUID(uuidString: "T1000001-0000-0000-0000-000000000000")!,
                fromDoctorID: UUID(uuidString: "E3000001-0000-0000-0000-000000000000")!,
                toDoctorID: currentDoctorID,
                shiftID: UUID(uuidString: "D2000001-0000-0000-0000-000000000000")!
            ),
            ShiftTradeRequest(
                id: UUID(uuidString: "T2000001-0000-0000-0000-000000000000")!,
                fromDoctorID: UUID(uuidString: "E7000001-0000-0000-0000-000000000000")!,
                toDoctorID: currentDoctorID,
                shiftID: UUID(uuidString: "D6000001-0000-0000-0000-000000000000")!
            ),
        ]
    }

    public var pendingTradeCount: Int { incomingTrades.filter { $0.state == .pending }.count }

    /// Seeds realistic upcoming shifts and trade partners when the doctor has no active shifts.
    /// Cleans up stale mock shifts seeded under a different doctor ID before checking.
    public func seedMockShiftsIfNeeded() {
        let docID = currentDoctorID
        assignedShifts.removeAll { Self.mockShiftIDs.contains($0.shift.id) && $0.doctorID != docID }
        guard activeAssignedShifts(for: docID).isEmpty else { return }
        buildAndInjectMockShifts(doctorID: docID)
        DoctorRosterStore.shared.seedMockDoctorsIfNeeded()
    }

    /// Removes all mock shifts and re-seeds fresh ones for the current doctor.
    public func resetMockData() {
        assignedShifts.removeAll { Self.mockShiftIDs.contains($0.shift.id) }
        buildAndInjectMockShifts(doctorID: currentDoctorID)
        DoctorRosterStore.shared.clearMockDoctors()
        DoctorRosterStore.shared.seedMockDoctorsIfNeeded()
    }

    private func buildAndInjectMockShifts(doctorID: UUID) {
        let cal = Calendar.current
        let now = Date()
        let hospital1 = UUID(uuidString: "B1A00001-0000-0000-0000-000000000000")!
        let hospital2 = UUID(uuidString: "B2A00001-0000-0000-0000-000000000000")!
        let hospital3 = UUID(uuidString: "B3A00001-0000-0000-0000-000000000000")!
        let assignedAt = cal.date(byAdding: .day, value: -7, to: now)!

        // Use the doctor's registered specialties so the shift visibility filter works correctly
        let profileSpecialties = DoctorProfile.load()?.specialties ?? []
        let sp1 = profileSpecialties.first ?? "Internal Medicine"
        let sp2 = profileSpecialties.dropFirst().first ?? sp1

        struct S { let id: UUID; let hospital: String; let hid: UUID
                   let specialty: String; let days: Int; let rate: Double
                   let status: DoctorShift.Status }

        let seeds: [S] = [
            S(id: UUID(uuidString: "D1000001-0000-0000-0000-000000000000")!,
              hospital: "St. Mary's Medical Center", hid: hospital1,
              specialty: sp1, days: 14, rate: 850, status: .scheduled),
            S(id: UUID(uuidString: "D2000001-0000-0000-0000-000000000000")!,
              hospital: "St. Mary's Medical Center", hid: hospital1,
              specialty: sp1, days: 7,  rate: 750, status: .scheduled),
            S(id: UUID(uuidString: "D3000001-0000-0000-0000-000000000000")!,
              hospital: "City General Hospital", hid: hospital2,
              specialty: sp2, days: 3,  rate: 700, status: .scheduled),
            S(id: UUID(uuidString: "D4000001-0000-0000-0000-000000000000")!,
              hospital: "St. Mary's Medical Center", hid: hospital1,
              specialty: sp1, days: 42, rate: 625, status: .tradedPending),
            S(id: UUID(uuidString: "D5000001-0000-0000-0000-000000000000")!,
              hospital: "Valley Health System", hid: hospital3,
              specialty: sp2, days: 60, rate: 500, status: .scheduled),
            S(id: UUID(uuidString: "D6000001-0000-0000-0000-000000000000")!,
              hospital: "City General Hospital", hid: hospital2,
              specialty: sp1, days: 21, rate: 780, status: .scheduled),
        ]

        let newShifts: [AssignedShift] = seeds.map { s in
            let date = cal.startOfDay(for: cal.date(byAdding: .day, value: s.days, to: now)!)
            let shift = Shift(id: s.id, hospitalID: s.hid, hospital: s.hospital,
                              specialty: s.specialty, start: date,
                              durationHours: 24, rateFloor: s.rate)
            return AssignedShift(shift: shift, doctorID: doctorID,
                                 status: s.status, assignedAt: assignedAt)
        }
        assignedShifts.append(contentsOf: newShifts)
        save()

        // Register each mock shift + a permissive policy so trade/cancel both work
        let mockPolicy = SchedulingPolicy(cancelWindowHours: 6, tradeWindowHours: 12)
        Task {
            for assigned in newShifts {
                await tradeService.upsertShift(
                    assigned.shift.toDoctorShift(doctorID: doctorID)
                )
                await tradeService.upsertPolicy(mockPolicy, for: assigned.shift.hospitalID)
            }
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        assignedShifts = stored.shifts
    }

    private func save() {
        let stored = Stored(shifts: assignedShifts)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Penalty Ledger (local until Stripe)

@MainActor
public final class PenaltyLedgerStore: ObservableObject {
    public static let shared = PenaltyLedgerStore()

    public enum EntryType: String, Codable { case cancel, trade }

    public struct Entry: Identifiable, Codable {
        public let id: UUID
        public let doctorID: UUID
        public let hospitalID: UUID
        public let shiftID: UUID
        public let type: EntryType
        public let amount: Decimal
        public let createdAt: Date
    }

    @Published public private(set) var entries: [Entry] = []
    private let storageKey = "penalty_ledger_v1"

    private init() { load() }

    public func record(doctorID: UUID, hospitalID: UUID, shiftID: UUID, type: EntryType, amount: Decimal) {
        entries.append(Entry(
            id: UUID(), doctorID: doctorID, hospitalID: hospitalID,
            shiftID: shiftID, type: type, amount: amount, createdAt: Date()
        ))
        save()
    }

    public func totalPenalties(for doctorID: UUID) -> Decimal {
        entries.filter { $0.doctorID == doctorID }.map(\.amount).reduce(0, +)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = stored
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Hospital Policy Store

@MainActor
public final class SchedulingPolicyStore: ObservableObject {
    public static let shared = SchedulingPolicyStore()

    @Published public var policy: SchedulingPolicy = SchedulingPolicy()
    private let storageKey = "hospital_scheduling_policy_v1"
    private var policiesByHospital: [UUID: SchedulingPolicy] = [:]

    public init() { load() }

    public func policy(for hospitalID: UUID) -> SchedulingPolicy {
        policiesByHospital[hospitalID] ?? policy
    }

    public func setPolicy(_ newPolicy: SchedulingPolicy, for hospitalID: UUID) {
        policiesByHospital[hospitalID] = newPolicy
        policy = newPolicy
        save()
        Task { await ShiftTradeService.shared.upsertPolicy(newPolicy, for: hospitalID) }
    }

    public func loadForHospital(_ profile: HospitalProfile?) {
        guard let profile else { return }
        var loaded = policiesByHospital[profile.id] ?? profile.schedulingPolicy
        loaded.cancellationPenaltyScale = SchedulingPolicy.normalizeCancellationScale(loaded.cancellationPenaltyScale)
        policy = loaded
        policiesByHospital[profile.id] = policy
    }

    public func saveForHospital(_ profile: HospitalProfile?) {
        guard let profile else { return }
        setPolicy(policy, for: profile.id)
        var updated = profile
        updated.schedulingPolicy = policy
        updated.save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([UUID: SchedulingPolicy].self, from: data) else { return }
        policiesByHospital = stored.mapValues { policy in
            var p = policy
            p.cancellationPenaltyScale = SchedulingPolicy.normalizeCancellationScale(p.cancellationPenaltyScale)
            return p
        }
        if let first = policiesByHospital.values.first { policy = first }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(policiesByHospital) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
