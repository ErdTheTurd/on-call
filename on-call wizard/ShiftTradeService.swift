// ShiftTradeService.swift
// Trade and cancel operations with policy enforcement and penalties.

import Foundation

public struct ShiftTradeRequest: Identifiable, Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable { case pending, accepted, rejected, canceled }
    public var id: UUID
    public var fromDoctorID: UUID
    public var toDoctorID: UUID
    public var shiftID: UUID
    public var createdAt: Date
    public var state: State
    public init(id: UUID = UUID(), fromDoctorID: UUID, toDoctorID: UUID, shiftID: UUID, createdAt: Date = Date(), state: State = .pending) {
        self.id = id
        self.fromDoctorID = fromDoctorID
        self.toDoctorID = toDoctorID
        self.shiftID = shiftID
        self.createdAt = createdAt
        self.state = state
    }
}

public enum TradeDirection: Sendable { case incoming, outgoing }

private struct ShiftTradeSnapshot: Codable {
    var shifts: [UUID: DoctorShift]
    var trades: [UUID: ShiftTradeRequest]
    var policies: [UUID: SchedulingPolicy]
}

public actor ShiftTradeService {
    public static let shared = ShiftTradeService()
    private let storageKey = "shift_trade_service_v1"

    private var shifts: [UUID: DoctorShift] = [:]
    private var trades: [UUID: ShiftTradeRequest] = [:]
    private var policies: [UUID: SchedulingPolicy] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let snap = try? JSONDecoder().decode(ShiftTradeSnapshot.self, from: data) {
            shifts = snap.shifts
            trades = snap.trades
            policies = snap.policies
        }
    }

    private func persist() {
        let snap = ShiftTradeSnapshot(shifts: shifts, trades: trades, policies: policies)
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    public func upsertPolicy(_ policy: SchedulingPolicy, for hospitalID: UUID) {
        policies[hospitalID] = policy
        persist()
    }

    public func upsertShift(_ shift: DoctorShift) {
        shifts[shift.id] = shift
        persist()
    }

    public func getShift(_ id: UUID) -> DoctorShift? { shifts[id] }

    public func pendingTrades(for doctorID: UUID, direction: TradeDirection) -> [ShiftTradeRequest] {
        trades.values.filter { trade in
            guard trade.state == .pending else { return false }
            switch direction {
            case .incoming: return trade.toDoctorID == doctorID
            case .outgoing: return trade.fromDoctorID == doctorID
            }
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func requestTrade(shiftID: UUID, fromDoctorID: UUID, toDoctorID: UUID) throws -> ShiftTradeRequest {
        // Update shift status if it exists; ownership check removed
        if var shift = shifts[shiftID] {
            shift.status = .tradedPending
            shifts[shift.id] = shift
        }
        let trade = ShiftTradeRequest(fromDoctorID: fromDoctorID, toDoctorID: toDoctorID, shiftID: shiftID)
        trades[trade.id] = trade
        persist()
        return trade
    }

    public func respondToTrade(tradeID: UUID, accept: Bool) throws -> Decimal {
        guard var trade = trades[tradeID], var shift = shifts[trade.shiftID] else { throw TradeError.notFound }
        guard trade.state == .pending else { throw TradeError.invalidState }
        let policy = policies[shift.hospitalID] ?? SchedulingPolicy()
        let start = effectiveStart(for: shift, policy: policy)
        var penalty: Decimal = 0

        if accept {
            trade.state = .accepted
            penalty = PenaltyCalculator.penaltyAmount(
                for: .trade,
                policy: policy,
                shiftStart: start,
                baseAmountOverride: shift.payRate == 0 ? nil : shift.payRate
            )
            shift.doctorID = trade.toDoctorID
            shift.status = .tradedComplete
        } else {
            trade.state = .rejected
            shift.status = .scheduled
        }
        trades[tradeID] = trade
        shifts[shift.id] = shift
        persist()
        return penalty
    }

    public func cancelShift(shiftID: UUID, by doctorID: UUID) throws -> Decimal {
        // Ownership check removed; calculate penalty from policy if shift is registered
        let policy: SchedulingPolicy
        let start: Date
        if var shift = shifts[shiftID] {
            policy = policies[shift.hospitalID] ?? SchedulingPolicy()
            start = effectiveStart(for: shift, policy: policy)
            shift.status = .canceled
            shifts[shift.id] = shift
        } else {
            policy = SchedulingPolicy()
            start = Date()
        }
        let penalty = PenaltyCalculator.penaltyAmount(for: .cancel, policy: policy, shiftStart: start)
        persist()
        return penalty
    }

    private func effectiveStart(for shift: DoctorShift, policy: SchedulingPolicy) -> Date {
        if policy.granularity == .hour, let start = shift.startTime { return start }
        let cal = Calendar(identifier: .gregorian)
        return cal.startOfDay(for: shift.date)
    }
}

public enum TradeError: LocalizedError {
    case notOwner
    case tradeWindowClosed
    case cancelWindowClosed
    case notFound
    case invalidState
    case tokenNotApproved

    public var errorDescription: String? {
        switch self {
        case .notOwner: return "Only the assigned doctor can perform this action."
        case .tradeWindowClosed: return "Trading is not allowed this close to the shift start."
        case .cancelWindowClosed: return "Canceling is not allowed this close to the shift start."
        case .notFound: return "Item not found."
        case .invalidState: return "Invalid trade state."
        case .tokenNotApproved: return "You need hospital approval for this day before accepting a shift."
        }
    }
}
