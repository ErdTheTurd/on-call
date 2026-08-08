// ShiftTradeService.swift
// Trade and cancel operations with policy enforcement and penalties.

import Foundation

public struct ShiftTradeRequest: Identifiable, Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable { case pending, accepted, rejected, canceled, countered }

    public var id: UUID
    /// Doctor offering to give up `shiftID`.
    public var fromDoctorID: UUID
    /// Doctor being asked to take `shiftID` and (optionally) give up `requestedShiftID`.
    public var toDoctorID: UUID
    /// Day the requester is giving up.
    public var shiftID: UUID
    /// Day the requester wants from the partner (day swap).
    public var requestedShiftID: UUID?
    /// Optional cash sweetener offered by the requester (or counter amount).
    public var compensationAmount: Double
    /// If this trade is a counter to another pending trade.
    public var counterOfTradeID: UUID?
    public var createdAt: Date
    public var state: State

    // Cached display fields (survive even if shifts move)
    public var fromDoctorName: String?
    public var toDoctorName: String?
    public var offeredDate: Date?
    public var requestedDate: Date?
    public var specialty: String?

    public init(
        id: UUID = UUID(),
        fromDoctorID: UUID,
        toDoctorID: UUID,
        shiftID: UUID,
        requestedShiftID: UUID? = nil,
        compensationAmount: Double = 0,
        counterOfTradeID: UUID? = nil,
        createdAt: Date = Date(),
        state: State = .pending,
        fromDoctorName: String? = nil,
        toDoctorName: String? = nil,
        offeredDate: Date? = nil,
        requestedDate: Date? = nil,
        specialty: String? = nil
    ) {
        self.id = id
        self.fromDoctorID = fromDoctorID
        self.toDoctorID = toDoctorID
        self.shiftID = shiftID
        self.requestedShiftID = requestedShiftID
        self.compensationAmount = max(0, min(1_000, compensationAmount))
        self.counterOfTradeID = counterOfTradeID
        self.createdAt = createdAt
        self.state = state
        self.fromDoctorName = fromDoctorName
        self.toDoctorName = toDoctorName
        self.offeredDate = offeredDate
        self.requestedDate = requestedDate
        self.specialty = specialty
    }

    enum CodingKeys: String, CodingKey {
        case id, fromDoctorID, toDoctorID, shiftID, requestedShiftID
        case compensationAmount, counterOfTradeID, createdAt, state
        case fromDoctorName, toDoctorName, offeredDate, requestedDate, specialty
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        fromDoctorID = try c.decode(UUID.self, forKey: .fromDoctorID)
        toDoctorID = try c.decode(UUID.self, forKey: .toDoctorID)
        shiftID = try c.decode(UUID.self, forKey: .shiftID)
        requestedShiftID = try c.decodeIfPresent(UUID.self, forKey: .requestedShiftID)
        compensationAmount = try c.decodeIfPresent(Double.self, forKey: .compensationAmount) ?? 0
        counterOfTradeID = try c.decodeIfPresent(UUID.self, forKey: .counterOfTradeID)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        state = try c.decodeIfPresent(State.self, forKey: .state) ?? .pending
        fromDoctorName = try c.decodeIfPresent(String.self, forKey: .fromDoctorName)
        toDoctorName = try c.decodeIfPresent(String.self, forKey: .toDoctorName)
        offeredDate = try c.decodeIfPresent(Date.self, forKey: .offeredDate)
        requestedDate = try c.decodeIfPresent(Date.self, forKey: .requestedDate)
        specialty = try c.decodeIfPresent(String.self, forKey: .specialty)
    }
}

public enum TradeDirection: Sendable { case incoming, outgoing }

private struct ShiftTradeSnapshot: Codable, Sendable {
    var shifts: [UUID: DoctorShift]
    var trades: [UUID: ShiftTradeRequest]
    var policies: [UUID: SchedulingPolicy]
}

/// MainActor class (not actor) so it shares isolation with SchedulingPolicy / PenaltyCalculator
/// under the project's default MainActor isolation — avoids Swift 6 concurrency alerts.
@MainActor
public final class ShiftTradeService {
    public static let shared = ShiftTradeService()
    private let storageKey = "shift_trade_service_v2"

    private var shifts: [UUID: DoctorShift] = [:]
    private var trades: [UUID: ShiftTradeRequest] = [:]
    private var policies: [UUID: SchedulingPolicy] = [:]

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let snap = try? JSONDecoder().decode(ShiftTradeSnapshot.self, from: data) {
            shifts = snap.shifts
            trades = snap.trades
            policies = snap.policies
        } else if let legacy = UserDefaults.standard.data(forKey: "shift_trade_service_v1"),
                  let snap = try? JSONDecoder().decode(ShiftTradeSnapshot.self, from: legacy) {
            shifts = snap.shifts
            trades = snap.trades
            policies = snap.policies
            persist()
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

    public func requestTrade(
        shiftID: UUID,
        fromDoctorID: UUID,
        toDoctorID: UUID,
        requestedShiftID: UUID? = nil,
        compensationAmount: Double = 0,
        counterOfTradeID: UUID? = nil,
        fromDoctorName: String? = nil,
        toDoctorName: String? = nil,
        offeredDate: Date? = nil,
        requestedDate: Date? = nil,
        specialty: String? = nil
    ) throws -> ShiftTradeRequest {
        guard fromDoctorID != toDoctorID else { throw TradeError.invalidState }
        if var shift = shifts[shiftID] {
            shift.status = .tradedPending
            shifts[shift.id] = shift
        }
        if let requestedShiftID, var wanted = shifts[requestedShiftID] {
            wanted.status = .tradedPending
            shifts[wanted.id] = wanted
        }
        if let parentID = counterOfTradeID, var parent = trades[parentID] {
            parent.state = .countered
            trades[parentID] = parent
        }
        let trade = ShiftTradeRequest(
            fromDoctorID: fromDoctorID,
            toDoctorID: toDoctorID,
            shiftID: shiftID,
            requestedShiftID: requestedShiftID,
            compensationAmount: compensationAmount,
            counterOfTradeID: counterOfTradeID,
            fromDoctorName: fromDoctorName,
            toDoctorName: toDoctorName,
            offeredDate: offeredDate ?? shifts[shiftID]?.date,
            requestedDate: requestedDate ?? requestedShiftID.flatMap { shifts[$0]?.date },
            specialty: specialty
        )
        trades[trade.id] = trade
        persist()
        return trade
    }

    public func respondToTrade(tradeID: UUID, accept: Bool) throws -> Decimal {
        guard var trade = trades[tradeID] else { throw TradeError.notFound }
        guard trade.state == .pending else { throw TradeError.invalidState }
        var offered = shifts[trade.shiftID]
        let policy = policies[offered?.hospitalID ?? UUID()] ?? SchedulingPolicy()
        let start = offered.map { effectiveStart(for: $0, policy: policy) } ?? Date()
        var penalty: Decimal = 0

        if accept {
            trade.state = .accepted
            penalty = PenaltyCalculator.penaltyAmount(
                for: .trade,
                policy: policy,
                shiftStart: start,
                baseAmountOverride: offered.flatMap { $0.payRate == 0 ? nil : $0.payRate }
            )
            if var o = offered {
                o.doctorID = trade.toDoctorID
                o.status = .tradedComplete
                shifts[o.id] = o
                offered = o
            }
            if let wantID = trade.requestedShiftID, var wanted = shifts[wantID] {
                wanted.doctorID = trade.fromDoctorID
                wanted.status = .scheduled
                shifts[wantID] = wanted
            }
        } else {
            trade.state = .rejected
            if var o = offered {
                o.status = .scheduled
                shifts[o.id] = o
            }
            if let wantID = trade.requestedShiftID, var wanted = shifts[wantID] {
                wanted.status = .scheduled
                shifts[wantID] = wanted
            }
        }
        trades[tradeID] = trade
        persist()
        return penalty
    }

    /// Drops a trade from the store (used when UI has a stale row).
    public func forceRemoveTrade(tradeID: UUID) {
        if var trade = trades[tradeID] {
            trade.state = .rejected
            trades[tradeID] = trade
        } else {
            trades.removeValue(forKey: tradeID)
        }
        persist()
    }

    public func clearAllTrades() {
        trades.removeAll()
        persist()
    }

    public func cancelShift(shiftID: UUID, by doctorID: UUID) throws -> Decimal {
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
    case missingRequestedDay

    public var errorDescription: String? {
        switch self {
        case .notOwner: return "Only the assigned doctor can perform this action."
        case .tradeWindowClosed: return "Trading is not allowed this close to the shift start."
        case .cancelWindowClosed: return "Canceling is not allowed this close to the shift start."
        case .notFound: return "Item not found."
        case .invalidState: return "Invalid trade state."
        case .tokenNotApproved: return "You need hospital approval for this day before accepting a shift."
        case .missingRequestedDay: return "Pick a day on their calendar to trade for."
        }
    }
}
