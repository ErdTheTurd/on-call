// SchedulingPolicy.swift
// Hospital on-call scheduling and penalty configuration.

import Foundation

public struct SchedulingPolicy: Codable, Sendable, Equatable {
    public enum Granularity: String, Codable, Sendable, CaseIterable { case day, hour }

    public var granularity: Granularity = .day

    /// When false, verified doctors are auto-approved and the pricing algorithm drives scheduling.
    public var administratorApproveShifts: Bool = false

    public struct PenaltyBracket: Codable, Sendable, Equatable {
        public var hoursBeforeStart: Int
        public var penaltyPercent: Double
        public init(hoursBeforeStart: Int, penaltyPercent: Double) {
            self.hoursBeforeStart = hoursBeforeStart
            self.penaltyPercent = penaltyPercent
        }
    }

    public var cancellationPenaltyScale: [PenaltyBracket]
    public var tradePenaltyScale: [PenaltyBracket]

    public var cancelWindowHours: Int
    public var tradeWindowHours: Int
    public var basePenaltyAmount: Decimal

    /// Master switch for trade penalty fees.
    public var tradePenaltiesEnabled: Bool = true
    /// Flat dollar fee when a trade occurs inside the lead-time window.
    public var tradePenaltyAmount: Decimal = 250
    /// Hours before shift start — inside this window the trade fee applies.
    public var tradePenaltyHoursBeforeStart: Int = 72

    /// Base pay per shift keyed by specialty name. Default $500 when absent.
    public var specialtyBaseRates: [String: Double] = [:]
    /// Per-doctor pay override keyed by doctorID.uuidString. Falls back to specialty rate.
    public var doctorBaseRates: [String: Double] = [:]

    private enum CodingKeys: String, CodingKey {
        case granularity, administratorApproveShifts
        case cancellationPenaltyScale, tradePenaltyScale
        case cancelWindowHours, tradeWindowHours, basePenaltyAmount
        case tradePenaltiesEnabled, tradePenaltyAmount, tradePenaltyHoursBeforeStart
        case specialtyBaseRates, doctorBaseRates
    }

    public init(
        granularity: Granularity = .day,
        administratorApproveShifts: Bool = false,
        cancellationPenaltyScale: [PenaltyBracket] = [
            .init(hoursBeforeStart: 24, penaltyPercent: 2.0)
        ],
        tradePenaltyScale: [PenaltyBracket] = [
            .init(hoursBeforeStart: 24, penaltyPercent: 0.25),
            .init(hoursBeforeStart: 72, penaltyPercent: 0.1),
            .init(hoursBeforeStart: 99999, penaltyPercent: 0.0)
        ],
        cancelWindowHours: Int = 6,
        tradeWindowHours: Int = 12,
        basePenaltyAmount: Decimal = 250,
        tradePenaltiesEnabled: Bool = true,
        tradePenaltyAmount: Decimal = 250,
        tradePenaltyHoursBeforeStart: Int = 72,
        specialtyBaseRates: [String: Double] = [:],
        doctorBaseRates: [String: Double] = [:]
    ) {
        self.granularity = granularity
        self.administratorApproveShifts = administratorApproveShifts
        self.cancellationPenaltyScale = cancellationPenaltyScale
        self.tradePenaltyScale = tradePenaltyScale
        self.cancelWindowHours = cancelWindowHours
        self.tradeWindowHours = tradeWindowHours
        self.basePenaltyAmount = basePenaltyAmount
        self.tradePenaltiesEnabled = tradePenaltiesEnabled
        self.tradePenaltyAmount = tradePenaltyAmount
        self.tradePenaltyHoursBeforeStart = tradePenaltyHoursBeforeStart
        self.specialtyBaseRates = specialtyBaseRates
        self.doctorBaseRates = doctorBaseRates
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        granularity = try c.decodeIfPresent(Granularity.self, forKey: .granularity) ?? .day
        administratorApproveShifts = try c.decodeIfPresent(Bool.self, forKey: .administratorApproveShifts) ?? false
        cancellationPenaltyScale = try c.decodeIfPresent([PenaltyBracket].self, forKey: .cancellationPenaltyScale) ?? Self().cancellationPenaltyScale
        cancellationPenaltyScale = Self.normalizeCancellationScale(cancellationPenaltyScale)
        tradePenaltyScale = try c.decodeIfPresent([PenaltyBracket].self, forKey: .tradePenaltyScale) ?? Self().tradePenaltyScale
        cancelWindowHours = try c.decodeIfPresent(Int.self, forKey: .cancelWindowHours) ?? 6
        tradeWindowHours = try c.decodeIfPresent(Int.self, forKey: .tradeWindowHours) ?? 12
        basePenaltyAmount = try c.decodeIfPresent(Decimal.self, forKey: .basePenaltyAmount) ?? 250
        tradePenaltiesEnabled = try c.decodeIfPresent(Bool.self, forKey: .tradePenaltiesEnabled) ?? true
        tradePenaltyAmount = try c.decodeIfPresent(Decimal.self, forKey: .tradePenaltyAmount) ?? 250
        tradePenaltyHoursBeforeStart = try c.decodeIfPresent(Int.self, forKey: .tradePenaltyHoursBeforeStart) ?? 72
        specialtyBaseRates = try c.decodeIfPresent([String: Double].self, forKey: .specialtyBaseRates) ?? [:]
        doctorBaseRates = try c.decodeIfPresent([String: Double].self, forKey: .doctorBaseRates) ?? [:]
    }

    public static func bracketLabel(for bracket: PenaltyBracket, previousHours: Int?) -> String {
        let pct = Int(bracket.penaltyPercent * 100)
        let window = PolicyLeadTimeFormatter.format(hours: bracket.hoursBeforeStart)
        if let prev = previousHours {
            let prevWindow = PolicyLeadTimeFormatter.format(hours: prev)
            return "\(prevWindow)–\(window) out: \(pct)% of base"
        }
        return "Within \(window): \(pct)% of base"
    }

    /// Clamps cancellation brackets to UI ranges and migrates legacy 0–100% values.
    static func normalizeCancellationScale(_ scale: [PenaltyBracket]) -> [PenaltyBracket] {
        let maxHours = 90 * 24
        // First pass: clamp percent and hours independently.
        var clamped = scale.map { bracket -> PenaltyBracket in
            var b = bracket
            if b.penaltyPercent < 1.0 { b.penaltyPercent = 1.0 }
            if b.penaltyPercent > 5.0 { b.penaltyPercent = 5.0 }
            if b.hoursBeforeStart > maxHours { b.hoursBeforeStart = maxHours }
            if b.hoursBeforeStart < 0 { b.hoursBeforeStart = 0 }
            return b
        }
        .sorted { $0.hoursBeforeStart < $1.hoursBeforeStart }
        // Second pass: enforce chain — each bracket's hours must be >= the previous one.
        for i in 1..<clamped.count {
            if clamped[i].hoursBeforeStart < clamped[i - 1].hoursBeforeStart {
                clamped[i].hoursBeforeStart = clamped[i - 1].hoursBeforeStart
            }
        }
        return clamped
    }
}

public enum SchedulingAction: Sendable { case cancel, trade }

public struct PolicyPreview: Sendable {
    public let allowed: Bool
    public let penaltyAmount: Decimal
    public let penaltyPercent: Double
    public let hoursRemaining: Double
    public let windowHours: Int
    public let action: SchedulingAction

    public var blockedReason: String? {
        guard !allowed else { return nil }
        switch action {
        case .cancel: return "Canceling is blocked within \(windowHours) hours of shift start."
        case .trade:  return "Trading is blocked within \(windowHours) hours of shift start."
        }
    }
}
