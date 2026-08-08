import Foundation
import Combine
import SwiftUI

// MARK: - Assigned Shifts Store (doctor-facing)

@MainActor
public final class AssignedShiftsStore: ObservableObject {
    public static let shared = AssignedShiftsStore()

    @Published public private(set) var assignedShifts: [AssignedShift] = [] {
        didSet { rebuildFilledIndex() }
    }
    @Published public private(set) var incomingTrades: [ShiftTradeRequest] = []
    @Published public private(set) var outgoingTrades: [ShiftTradeRequest] = []
    @Published public var lastError: String?

    public var currentDoctorID: UUID { SessionStore.shared.currentDoctorID }

    /// Fast lookup for filled shifts (avoids O(n) scan per calendar cell).
    private var filledShiftIDs: Set<UUID> = []

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
        rebuildFilledIndex()
        syncFromService()
    }

    private func rebuildFilledIndex() {
        filledShiftIDs = Set(
            assignedShifts
                .filter { $0.status != .canceled }
                .map(\.shift.id)
        )
    }

    public func assign(_ shift: Shift, doctorID: UUID? = nil) async {
        let docID = doctorID ?? currentDoctorID
        let assigned = AssignedShift(shift: shift, doctorID: docID)
        assignedShifts.append(assigned)
        save()
        tradeService.upsertShift(shift.toDoctorShift(doctorID: docID))
        let policy = SchedulingPolicyStore.shared.policy(for: shift.hospitalID)
        tradeService.upsertPolicy(policy, for: shift.hospitalID)
    }

    /// Synchronous seed helper for investor demo. Skips if shift already assigned.
    public func seedAssignmentIfNeeded(shift: Shift, doctorID: UUID) {
        if assignedShifts.contains(where: { $0.shift.id == shift.id && $0.status != .canceled }) { return }
        assignedShifts.append(AssignedShift(shift: shift, doctorID: doctorID))
        save()
    }

    public func cancelShift(_ assigned: AssignedShift) async throws -> Decimal {
        lastError = nil
        let policy = SchedulingPolicyStore.shared.policy(for: assigned.shift.hospitalID)
        let start = effectiveStart(for: assigned.shift, policy: policy)
        let preview = PenaltyCalculator.preview(for: .cancel, policy: policy, shiftStart: start, baseAmountOverride: Decimal(assigned.shift.totalEarnings))
        guard preview.allowed else { throw TradeError.cancelWindowClosed }

        let penalty = try tradeService.cancelShift(shiftID: assigned.shift.id, by: assigned.doctorID)
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

    /// Days the partner can give you in a swap (read-only — never mutates during view updates).
    public func tradeableShifts(
        forPartner doctorID: UUID,
        specialty: String,
        excludingDate: Date
    ) -> [AssignedShift] {
        let cal = Calendar.current
        return assignedShifts
            .filter {
                $0.doctorID == doctorID &&
                $0.status != .canceled &&
                !$0.shift.isPast &&
                DoctorPreferencesStore.specialtyMatches($0.shift.specialty, specialty) &&
                !cal.isDate($0.shift.date, inSameDayAs: excludingDate)
            }
            .sorted { $0.shift.date < $1.shift.date }
    }

    /// Call when a doctor is selected for trade — seeds demo partner days if needed (not during body).
    public func preparePartnerTradeDays(
        forPartner doctorID: UUID,
        specialty: String,
        excludingDate: Date
    ) {
        let existing = tradeableShifts(forPartner: doctorID, specialty: specialty, excludingDate: excludingDate)
        guard existing.isEmpty else { return }
        _ = ensureDemoPartnerShifts(doctorID: doctorID, specialty: specialty, excludingDate: excludingDate)
    }

    /// Alternate days the current doctor can offer when countering an incoming trade.
    public func counterAlternateDays(for trade: ShiftTradeRequest) -> [AssignedShift] {
        let excluded = Set([trade.shiftID, trade.requestedShiftID].compactMap { $0 })
        var days = activeAssignedShifts().filter {
            !excluded.contains($0.shift.id) && !$0.shift.isPast
        }
        if days.count < 2 {
            let needed = 2 - days.count
            let created = ensureCounterDaysForCurrentDoctor(
                count: needed,
                specialty: trade.specialty
                    ?? activeAssignedShifts().first?.shift.specialty
                    ?? "Internal Medicine",
                excluding: excluded
            )
            days.append(contentsOf: created)
        }
        return days.sorted { $0.shift.date < $1.shift.date }
    }

    public func requestTrade(
        for assigned: AssignedShift,
        toDoctor: DoctorSummary,
        requestedShift: AssignedShift,
        compensationAmount: Double
    ) async throws -> ShiftTradeRequest {
        lastError = nil
        guard assigned.shift.id != requestedShift.shift.id else { throw TradeError.invalidState }

        tradeService.upsertShift(assigned.shift.toDoctorShift(doctorID: assigned.doctorID))
        tradeService.upsertShift(requestedShift.shift.toDoctorShift(doctorID: requestedShift.doctorID))
        let policy = SchedulingPolicyStore.shared.policy(for: assigned.shift.hospitalID)
        tradeService.upsertPolicy(policy, for: assigned.shift.hospitalID)

        let fromName = DoctorProfile.load().map { "Dr. \($0.lastName)" }
            ?? DoctorRosterStore.shared.doctors.first(where: { $0.id == assigned.doctorID })?.name
        let trade = try tradeService.requestTrade(
            shiftID: assigned.shift.id,
            fromDoctorID: assigned.doctorID,
            toDoctorID: toDoctor.id,
            requestedShiftID: requestedShift.shift.id,
            compensationAmount: compensationAmount,
            fromDoctorName: fromName,
            toDoctorName: toDoctor.name,
            offeredDate: assigned.shift.date,
            requestedDate: requestedShift.shift.date,
            specialty: assigned.shift.specialty
        )
        if let idx = assignedShifts.firstIndex(where: { $0.id == assigned.id }) {
            assignedShifts[idx].status = .tradedPending
        }
        if let idx = assignedShifts.firstIndex(where: { $0.id == requestedShift.id }) {
            assignedShifts[idx].status = .tradedPending
        }
        save()
        syncFromService()
        return trade
    }

    /// Counter: keep their offered day, but swap a different day of yours + optional new compensation.
    public func counterTrade(
        original: ShiftTradeRequest,
        newRequestedShift: AssignedShift,
        compensationAmount: Double
    ) async throws -> ShiftTradeRequest {
        lastError = nil
        guard original.toDoctorID == currentDoctorID else { throw TradeError.invalidState }
        guard original.state == .pending else { throw TradeError.invalidState }
        guard newRequestedShift.shift.id != original.requestedShiftID else {
            throw TradeError.missingRequestedDay
        }

        // Always register both sides so the trade service can complete later.
        if let offered = assignedShifts.first(where: { $0.shift.id == original.shiftID }) {
            tradeService.upsertShift(offered.shift.toDoctorShift(doctorID: offered.doctorID))
        } else if let offeredDate = original.offeredDate {
            let placeholder = Shift(
                id: original.shiftID,
                hospitalID: newRequestedShift.shift.hospitalID,
                hospital: newRequestedShift.shift.hospital,
                specialty: original.specialty ?? newRequestedShift.shift.specialty,
                start: offeredDate,
                durationHours: 24,
                rateFloor: 650
            )
            tradeService.upsertShift(placeholder.toDoctorShift(doctorID: original.fromDoctorID))
        }
        tradeService.upsertShift(newRequestedShift.shift.toDoctorShift(doctorID: newRequestedShift.doctorID))

        let fromName = original.fromDoctorName
            ?? DoctorRosterStore.shared.doctors.first(where: { $0.id == original.fromDoctorID })?.name
        let toName = DoctorProfile.load().map { "Dr. \($0.lastName)" }
            ?? DoctorRosterStore.shared.doctors.first(where: { $0.id == currentDoctorID })?.name

        let trade = try tradeService.requestTrade(
            shiftID: original.shiftID,
            fromDoctorID: original.fromDoctorID,
            toDoctorID: original.toDoctorID,
            requestedShiftID: newRequestedShift.shift.id,
            compensationAmount: compensationAmount,
            counterOfTradeID: original.id,
            fromDoctorName: fromName,
            toDoctorName: toName,
            offeredDate: original.offeredDate,
            requestedDate: newRequestedShift.shift.date,
            specialty: original.specialty ?? newRequestedShift.shift.specialty
        )
        if let oldID = original.requestedShiftID,
           oldID != newRequestedShift.shift.id,
           let idx = assignedShifts.firstIndex(where: { $0.shift.id == oldID }) {
            assignedShifts[idx].status = .scheduled
        }
        if let idx = assignedShifts.firstIndex(where: { $0.id == newRequestedShift.id }) {
            assignedShifts[idx].status = .tradedPending
        }
        save()
        syncFromService()
        return trade
    }

    public func respondToTrade(_ trade: ShiftTradeRequest, accept: Bool) async throws -> Decimal {
        lastError = nil

        // Make sure the service can resolve ownership even if the shift was demo-only.
        if let offered = assignedShifts.first(where: { $0.shift.id == trade.shiftID }) {
            tradeService.upsertShift(offered.shift.toDoctorShift(doctorID: offered.doctorID))
            tradeService.upsertPolicy(
                SchedulingPolicyStore.shared.policy(for: offered.shift.hospitalID),
                for: offered.shift.hospitalID
            )
        }
        if let wantID = trade.requestedShiftID,
           let wanted = assignedShifts.first(where: { $0.shift.id == wantID }) {
            tradeService.upsertShift(wanted.shift.toDoctorShift(doctorID: wanted.doctorID))
        }

        let penalty: Decimal
        do {
            penalty = try tradeService.respondToTrade(tradeID: trade.id, accept: accept)
        } catch let error as TradeError {
            switch error {
            case .notFound, .invalidState:
                penalty = 0
                tradeService.forceRemoveTrade(tradeID: trade.id)
            default:
                throw error
            }
        }

        if accept {
            if let idx = assignedShifts.firstIndex(where: { $0.shift.id == trade.shiftID }) {
                assignedShifts[idx].doctorID = trade.toDoctorID
                assignedShifts[idx].status = .scheduled
            } else if let date = trade.offeredDate {
                // Partner's offered day wasn't in our roster — claim it.
                let specialty = trade.specialty
                    ?? activeAssignedShifts().first?.shift.specialty
                    ?? "Internal Medicine"
                let hospitalID = UUID(uuidString: "B1A00001-0000-0000-0000-000000000000")!
                let shift = Shift(
                    id: trade.shiftID,
                    hospitalID: hospitalID,
                    hospital: "St. Mary's Medical Center",
                    specialty: specialty,
                    start: date,
                    durationHours: 24,
                    rateFloor: 650
                )
                assignedShifts.append(
                    AssignedShift(shift: shift, doctorID: trade.toDoctorID, status: .scheduled)
                )
            }
            if let wantID = trade.requestedShiftID,
               let idx = assignedShifts.firstIndex(where: { $0.shift.id == wantID }) {
                assignedShifts[idx].doctorID = trade.fromDoctorID
                assignedShifts[idx].status = .scheduled
            }
            if penalty > 0, let assigned = assignedShifts.first(where: { $0.shift.id == trade.shiftID }) {
                PenaltyLedgerStore.shared.record(
                    doctorID: trade.fromDoctorID,
                    hospitalID: assigned.shift.hospitalID,
                    shiftID: trade.shiftID,
                    type: .trade,
                    amount: penalty
                )
            }
        } else {
            if let idx = assignedShifts.firstIndex(where: { $0.shift.id == trade.shiftID }) {
                assignedShifts[idx].status = .scheduled
            }
            if let wantID = trade.requestedShiftID,
               let idx = assignedShifts.firstIndex(where: { $0.shift.id == wantID }) {
                assignedShifts[idx].status = .scheduled
            }
        }
        save()
        syncFromService()
        if incomingTrades.contains(where: { $0.id == trade.id }) {
            incomingTrades.removeAll { $0.id == trade.id }
        }
        return penalty
    }

    public func doctorName(for id: UUID) -> String {
        if let name = DoctorRosterStore.shared.doctors.first(where: { $0.id == id })?.name {
            return name
        }
        if let p = DoctorProfile.load(), p.id == id {
            return "Dr. \(p.lastName)"
        }
        return "Doctor"
    }

    private var cachedSpecialties: [String] {
        DoctorProfile.load()?.specialties ?? []
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
        let mine = assignedShifts.filter { $0.doctorID == id && $0.status != .canceled && !$0.shift.isPast }
        let specialties = cachedSpecialties
        guard !specialties.isEmpty else { return mine }
        return mine.filter { shift in
            specialties.contains { DoctorPreferencesStore.specialtyMatches($0, shift.shift.specialty) }
        }
    }

    public func completedShifts(for doctorID: UUID? = nil) -> [AssignedShift] {
        let id = doctorID ?? currentDoctorID
        let mine = assignedShifts.filter { $0.doctorID == id && $0.status != .canceled && $0.shift.isPast }
        let specialties = cachedSpecialties
        guard !specialties.isEmpty else { return mine }
        return mine.filter { shift in
            specialties.contains { DoctorPreferencesStore.specialtyMatches($0, shift.shift.specialty) }
        }
    }

    public func totalEarnings(for doctorID: UUID? = nil) -> Double {
        activeAssignedShifts(for: doctorID).map(\.shift.totalEarnings).reduce(0, +)
            + completedShifts(for: doctorID).map(\.shift.totalEarnings).reduce(0, +)
    }

    public func assignedDoctorID(for shiftID: UUID) -> UUID? {
        assignedShifts.first { $0.shift.id == shiftID && $0.status != .canceled }?.doctorID
    }

    /// True when the current doctor already holds a (non-canceled) shift on this day.
    public func isScheduled(on date: Date, doctorID: UUID? = nil) -> Bool {
        let id = doctorID ?? currentDoctorID
        let cal = Calendar.current
        return assignedShifts.contains {
            $0.doctorID == id &&
            $0.status != .canceled &&
            cal.isDate($0.shift.date, inSameDayAs: date)
        }
    }

    public func isShiftFilled(_ shiftID: UUID) -> Bool {
        filledShiftIDs.contains(shiftID)
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

    private func syncFromService() {
        incomingTrades = tradeService.pendingTrades(for: currentDoctorID, direction: .incoming)
        outgoingTrades = tradeService.pendingTrades(for: currentDoctorID, direction: .outgoing)
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

    /// Seeds two realistic incoming trade offers into the trade service (not a local-only array).
    public func seedMockIncomingTradesIfNeeded() {
        syncFromService()
        guard incomingTrades.isEmpty else { return }
        DoctorRosterStore.shared.seedMockDoctorsIfNeeded()

        let mine = activeAssignedShifts().filter { $0.status == .scheduled }
        guard let myDay = mine.first else { return }

        let partners = DoctorRosterStore.shared.eligibleTradePartners(
            for: myDay.shift.specialty,
            excluding: currentDoctorID
        )
        guard partners.count >= 1 else { return }

        let partnerA = partners[0]
        let partnerB = partners.count > 1 ? partners[1] : partners[0]
        let offeredA = ensureDemoPartnerShifts(
            doctorID: partnerA.id,
            specialty: myDay.shift.specialty,
            excludingDate: myDay.shift.date
        )
        let offeredB = ensureDemoPartnerShifts(
            doctorID: partnerB.id,
            specialty: myDay.shift.specialty,
            excludingDate: myDay.shift.date
        )
        guard let dayA = offeredA.first, let dayB = offeredB.dropFirst().first ?? offeredB.first else { return }

        let mySecond = mine.dropFirst().first ?? myDay

        let policy = SchedulingPolicy(cancelWindowHours: 6, tradeWindowHours: 12)
        for item in [dayA, dayB, myDay, mySecond] {
            tradeService.upsertShift(item.shift.toDoctorShift(doctorID: item.doctorID))
            tradeService.upsertPolicy(policy, for: item.shift.hospitalID)
        }

        _ = try? tradeService.requestTrade(
            shiftID: dayA.shift.id,
            fromDoctorID: partnerA.id,
            toDoctorID: currentDoctorID,
            requestedShiftID: myDay.shift.id,
            compensationAmount: 250,
            fromDoctorName: partnerA.name,
            toDoctorName: DoctorProfile.load().map { "Dr. \($0.lastName)" },
            offeredDate: dayA.shift.date,
            requestedDate: myDay.shift.date,
            specialty: myDay.shift.specialty
        )
        _ = try? tradeService.requestTrade(
            shiftID: dayB.shift.id,
            fromDoctorID: partnerB.id,
            toDoctorID: currentDoctorID,
            requestedShiftID: mySecond.shift.id,
            compensationAmount: 100,
            fromDoctorName: partnerB.name,
            toDoctorName: DoctorProfile.load().map { "Dr. \($0.lastName)" },
            offeredDate: dayB.shift.date,
            requestedDate: mySecond.shift.date,
            specialty: myDay.shift.specialty
        )
        // Keep my days scheduled so Counter always has alternates and Accept can reassign cleanly.
        save()
        syncFromService()
    }

    /// Extra upcoming days for the current doctor so Counter is never empty.
    private func ensureCounterDaysForCurrentDoctor(
        count: Int,
        specialty: String,
        excluding: Set<UUID>
    ) -> [AssignedShift] {
        guard count > 0 else { return [] }
        let cal = Calendar.current
        let hospitalID = UUID(uuidString: "B1A00001-0000-0000-0000-000000000000")!
        var created: [AssignedShift] = []
        var slot = 0
        var dayOffset = 8
        while created.count < count && slot < 12 {
            let date = cal.startOfDay(for: cal.date(byAdding: .day, value: dayOffset, to: Date())!)
            dayOffset += 6
            let id = Self.demoPartnerShiftID(doctorID: currentDoctorID, slot: 40 + slot)
            slot += 1
            if excluding.contains(id) { continue }
            if let existing = assignedShifts.first(where: { $0.shift.id == id }) {
                if existing.doctorID == currentDoctorID, existing.status != .canceled, !existing.shift.isPast {
                    created.append(existing)
                }
                continue
            }
            if assignedShifts.contains(where: {
                $0.doctorID == currentDoctorID && cal.isDate($0.shift.date, inSameDayAs: date)
            }) { continue }
            let shift = Shift(
                id: id,
                hospitalID: hospitalID,
                hospital: "St. Mary's Medical Center",
                specialty: specialty,
                start: date,
                durationHours: 24,
                rateFloor: 650
            )
            let assigned = AssignedShift(shift: shift, doctorID: currentDoctorID, status: .scheduled)
            assignedShifts.append(assigned)
            tradeService.upsertShift(shift.toDoctorShift(doctorID: currentDoctorID))
            created.append(assigned)
        }
        if !created.isEmpty { save() }
        return created
    }

    /// Creates a handful of upcoming partner shifts so the trade calendar is never empty in demo.
    @discardableResult
    private func ensureDemoPartnerShifts(
        doctorID: UUID,
        specialty: String,
        excludingDate: Date
    ) -> [AssignedShift] {
        let cal = Calendar.current
        let existing = assignedShifts.filter {
            $0.doctorID == doctorID &&
            $0.status == .scheduled &&
            !$0.shift.isPast &&
            DoctorPreferencesStore.specialtyMatches($0.shift.specialty, specialty) &&
            !cal.isDate($0.shift.date, inSameDayAs: excludingDate)
        }
        if !existing.isEmpty {
            return existing.sorted { $0.shift.date < $1.shift.date }
        }

        let hospitalID = UUID(uuidString: "B1A00001-0000-0000-0000-000000000000")!
        let hospitalName = "St. Mary's Medical Center"
        let dayOffsets = [5, 12, 19, 26, 33]
        var created: [AssignedShift] = []
        for (i, offset) in dayOffsets.enumerated() {
            let date = cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: Date())!)
            if cal.isDate(date, inSameDayAs: excludingDate) { continue }
            let id = Self.demoPartnerShiftID(doctorID: doctorID, slot: i)
            if let found = assignedShifts.first(where: { $0.shift.id == id }) {
                created.append(found)
                continue
            }
            let shift = Shift(
                id: id,
                hospitalID: hospitalID,
                hospital: hospitalName,
                specialty: specialty,
                start: date,
                durationHours: 24,
                rateFloor: 650
            )
            let assigned = AssignedShift(shift: shift, doctorID: doctorID, status: .scheduled)
            assignedShifts.append(assigned)
            tradeService.upsertShift(shift.toDoctorShift(doctorID: doctorID))
            created.append(assigned)
        }
        save()
        return created.sorted { $0.shift.date < $1.shift.date }
    }

    /// Deterministic UUID so partner demo days don't multiply across launches.
    private static func demoPartnerShiftID(doctorID: UUID, slot: Int) -> UUID {
        var b = doctorID.uuid
        b.0 = 0xF0
        b.1 = UInt8(slot & 0xFF)
        b.2 = 0xDE
        b.3 = 0x40
        return UUID(uuid: b)
    }

    public var pendingTradeCount: Int { incomingTrades.filter { $0.state == .pending }.count }

    /// Seeds realistic upcoming shifts and trade partners when the doctor has no active shifts.
    /// Cleans up stale mock shifts seeded under a different doctor ID before checking.
    public func seedMockShiftsIfNeeded() {
        let docID = currentDoctorID
        let specialties = DoctorProfile.load()?.specialties ?? []
        assignedShifts.removeAll { Self.mockShiftIDs.contains($0.shift.id) && $0.doctorID != docID }
        // Drop mock shifts that don't match the doctor's specialty (old seeds / naming drift).
        if !specialties.isEmpty {
            assignedShifts.removeAll { entry in
                guard Self.mockShiftIDs.contains(entry.shift.id), entry.doctorID == docID else { return false }
                return !specialties.contains {
                    DoctorPreferencesStore.specialtyMatches($0, entry.shift.specialty)
                }
            }
            save()
        }
        guard activeAssignedShifts(for: docID).isEmpty else { return }
        buildAndInjectMockShifts(doctorID: docID)
        DoctorRosterStore.shared.seedMockDoctorsIfNeeded()
    }

    /// Removes all mock shifts and re-seeds fresh ones for the current doctor.
    public func resetMockData() {
        assignedShifts.removeAll { Self.mockShiftIDs.contains($0.shift.id) }
        // Also drop synthetic partner / counter demo days.
        assignedShifts.removeAll { shift in
            var bytes = shift.shift.id.uuid
            return bytes.0 == 0xF0 && bytes.2 == 0xDE && bytes.3 == 0x40
        }
        tradeService.clearAllTrades()
        incomingTrades = []
        outgoingTrades = []
        buildAndInjectMockShifts(doctorID: currentDoctorID)
        DoctorRosterStore.shared.clearMockDoctors()
        DoctorRosterStore.shared.seedMockDoctorsIfNeeded()
        seedMockIncomingTradesIfNeeded()
    }

    private func buildAndInjectMockShifts(doctorID: UUID) {
        let cal = Calendar.current
        let now = Date()
        let hospital1 = UUID(uuidString: "B1A00001-0000-0000-0000-000000000000")!
        let hospital2 = UUID(uuidString: "B2A00001-0000-0000-0000-000000000000")!
        let hospital3 = UUID(uuidString: "B3A00001-0000-0000-0000-000000000000")!
        let assignedAt = cal.date(byAdding: .day, value: -7, to: now)!

        // Only the doctor's registered specialty — never invent a second one.
        let profileSpecialties = DoctorProfile.load()?.specialties ?? []
        let sp1 = profileSpecialties.first ?? "Internal Medicine"

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
              specialty: sp1, days: 3,  rate: 700, status: .scheduled),
            S(id: UUID(uuidString: "D4000001-0000-0000-0000-000000000000")!,
              hospital: "St. Mary's Medical Center", hid: hospital1,
              specialty: sp1, days: 42, rate: 625, status: .tradedPending),
            S(id: UUID(uuidString: "D5000001-0000-0000-0000-000000000000")!,
              hospital: "Valley Health System", hid: hospital3,
              specialty: sp1, days: 60, rate: 500, status: .scheduled),
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
        for assigned in newShifts {
            tradeService.upsertShift(assigned.shift.toDoctorShift(doctorID: doctorID))
            tradeService.upsertPolicy(mockPolicy, for: assigned.shift.hospitalID)
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
        ShiftTradeService.shared.upsertPolicy(newPolicy, for: hospitalID)
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
