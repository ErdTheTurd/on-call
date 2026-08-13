// SchedulingPolicy.swift
// Hospital on-call scheduling and penalty configuration.

import Foundation

public struct SchedulingPolicy: Codable, Sendable, Equatable {
    public enum Granularity: String, Codable, Sendable, CaseIterable { case day, hour }

    public var granularity: Granularity = .day

    /// When false, verified doctors are auto-approved and the pricing algorithm drives scheduling.
    public var administratorApproveShifts: Bool = true

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

    /// Global default: `true` = On Call algorithm pricing; `false` = hospital proprietary set rates.
    public var useAlgorithmPricingByDefault: Bool = true
    /// Per-specialty override. `true` = algorithm, `false` = proprietary. Missing → `useAlgorithmPricingByDefault`.
    public var specialtyUsesAlgorithm: [String: Bool] = [:]

    /// Pricing factor IDs that are turned off in Alter Shifts (all others are on).
    public var disabledPricingVariables: [String] = []
    /// Case volume premium (surgical block reward) — off = scale treated as 0.
    public var caseVolumeRewardEnabled: Bool = true
    /// Compensation intensity 10…100 in steps of 10. Algo auto-sets from 3‑month case volume.
    public var caseVolumeRewardScale: Int = 40
    /// When true, Recalculate overwrites `caseVolumeRewardScale` from the algo.
    public var caseVolumeRewardAuto: Bool = true

    /// Default daily request tokens for the whole roster (0…20).
    public var defaultDailyTokens: Int = 3
    /// Per-doctor token exceptions keyed by doctorID.uuidString. Missing → `defaultDailyTokens`.
    public var doctorTokenLimits: [String: Int] = [:]

    public static let minDailyTokens = 0
    public static let maxDailyTokens = 20

    private enum CodingKeys: String, CodingKey {
        case granularity, administratorApproveShifts
        case cancellationPenaltyScale, tradePenaltyScale
        case cancelWindowHours, tradeWindowHours, basePenaltyAmount
        case tradePenaltiesEnabled, tradePenaltyAmount, tradePenaltyHoursBeforeStart
        case specialtyBaseRates, doctorBaseRates
        case useAlgorithmPricingByDefault, specialtyUsesAlgorithm
        case disabledPricingVariables, caseVolumeRewardEnabled
        case caseVolumeRewardScale, caseVolumeRewardAuto
        case defaultDailyTokens, doctorTokenLimits
    }

    public init(
        granularity: Granularity = .day,
        administratorApproveShifts: Bool = true,
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
        basePenaltyAmount: Decimal = 0,
        tradePenaltiesEnabled: Bool = true,
        tradePenaltyAmount: Decimal = 250,
        tradePenaltyHoursBeforeStart: Int = 72,
        specialtyBaseRates: [String: Double] = [:],
        doctorBaseRates: [String: Double] = [:],
        useAlgorithmPricingByDefault: Bool = true,
        specialtyUsesAlgorithm: [String: Bool] = [:],
        disabledPricingVariables: [String] = [],
        caseVolumeRewardEnabled: Bool = true,
        caseVolumeRewardScale: Int = 40,
        caseVolumeRewardAuto: Bool = true,
        defaultDailyTokens: Int = 3,
        doctorTokenLimits: [String: Int] = [:]
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
        self.useAlgorithmPricingByDefault = useAlgorithmPricingByDefault
        self.specialtyUsesAlgorithm = specialtyUsesAlgorithm
        self.disabledPricingVariables = disabledPricingVariables
        self.caseVolumeRewardEnabled = caseVolumeRewardEnabled
        self.caseVolumeRewardScale = Self.clampCaseVolumeScale(caseVolumeRewardScale)
        self.caseVolumeRewardAuto = caseVolumeRewardAuto
        self.defaultDailyTokens = min(20, max(0, defaultDailyTokens))
        self.doctorTokenLimits = doctorTokenLimits.mapValues { min(20, max(0, $0)) }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        granularity = try c.decodeIfPresent(Granularity.self, forKey: .granularity) ?? .day
        administratorApproveShifts = try c.decodeIfPresent(Bool.self, forKey: .administratorApproveShifts) ?? true
        cancellationPenaltyScale = try c.decodeIfPresent([PenaltyBracket].self, forKey: .cancellationPenaltyScale) ?? Self().cancellationPenaltyScale
        cancellationPenaltyScale = Self.normalizeCancellationScale(cancellationPenaltyScale)
        tradePenaltyScale = try c.decodeIfPresent([PenaltyBracket].self, forKey: .tradePenaltyScale) ?? Self().tradePenaltyScale
        cancelWindowHours = try c.decodeIfPresent(Int.self, forKey: .cancelWindowHours) ?? 6
        tradeWindowHours = try c.decodeIfPresent(Int.self, forKey: .tradeWindowHours) ?? 12
        basePenaltyAmount = try c.decodeIfPresent(Decimal.self, forKey: .basePenaltyAmount) ?? 0
        tradePenaltiesEnabled = try c.decodeIfPresent(Bool.self, forKey: .tradePenaltiesEnabled) ?? true
        tradePenaltyAmount = try c.decodeIfPresent(Decimal.self, forKey: .tradePenaltyAmount) ?? 250
        tradePenaltyHoursBeforeStart = try c.decodeIfPresent(Int.self, forKey: .tradePenaltyHoursBeforeStart) ?? 72
        specialtyBaseRates = try c.decodeIfPresent([String: Double].self, forKey: .specialtyBaseRates) ?? [:]
        doctorBaseRates = try c.decodeIfPresent([String: Double].self, forKey: .doctorBaseRates) ?? [:]
        useAlgorithmPricingByDefault = try c.decodeIfPresent(Bool.self, forKey: .useAlgorithmPricingByDefault) ?? true
        specialtyUsesAlgorithm = try c.decodeIfPresent([String: Bool].self, forKey: .specialtyUsesAlgorithm) ?? [:]
        disabledPricingVariables = try c.decodeIfPresent([String].self, forKey: .disabledPricingVariables) ?? []
        caseVolumeRewardEnabled = try c.decodeIfPresent(Bool.self, forKey: .caseVolumeRewardEnabled) ?? true
        caseVolumeRewardScale = Self.clampCaseVolumeScale(
            try c.decodeIfPresent(Int.self, forKey: .caseVolumeRewardScale) ?? 40
        )
        caseVolumeRewardAuto = try c.decodeIfPresent(Bool.self, forKey: .caseVolumeRewardAuto) ?? true
        defaultDailyTokens = min(20, max(0, try c.decodeIfPresent(Int.self, forKey: .defaultDailyTokens) ?? 3))
        doctorTokenLimits = (try c.decodeIfPresent([String: Int].self, forKey: .doctorTokenLimits) ?? [:])
            .mapValues { min(20, max(0, $0)) }
    }

    public static func clampCaseVolumeScale(_ value: Int) -> Int {
        let stepped = Int((Double(value) / 10.0).rounded()) * 10
        return min(100, max(10, stepped))
    }

    nonisolated public static func clampDailyTokens(_ value: Int) -> Int {
        min(20, max(0, value))
    }

    /// Tokens/day for one doctor at this hospital (override or roster default).
    public func dailyTokenLimit(forDoctorID doctorID: UUID) -> Int {
        if let override = doctorTokenLimits[doctorID.uuidString] {
            return Self.clampDailyTokens(override)
        }
        return Self.clampDailyTokens(defaultDailyTokens)
    }

    public func hasCustomTokenLimit(forDoctorID doctorID: UUID) -> Bool {
        doctorTokenLimits[doctorID.uuidString] != nil
    }

    public mutating func setDailyTokenLimit(_ limit: Int?, forDoctorID doctorID: UUID) {
        let key = doctorID.uuidString
        if let limit {
            doctorTokenLimits[key] = Self.clampDailyTokens(limit)
        } else {
            doctorTokenLimits.removeValue(forKey: key)
        }
    }

    public func usesAlgorithmPricing(for specialty: String) -> Bool {
        specialtyUsesAlgorithm[specialty] ?? useAlgorithmPricingByDefault
    }

    public mutating func setUsesAlgorithmPricing(_ useAlgorithm: Bool, for specialty: String) {
        specialtyUsesAlgorithm[specialty] = useAlgorithm
    }

    public mutating func setUsesAlgorithmPricing(_ useAlgorithm: Bool, forSpecialties specialties: [String]) {
        for sp in specialties {
            specialtyUsesAlgorithm[sp] = useAlgorithm
        }
        if specialties.count > 1 {
            useAlgorithmPricingByDefault = useAlgorithm
        }
    }

    public func isPricingVariableEnabled(_ id: String) -> Bool {
        if id == "caseVolume" { return caseVolumeRewardEnabled }
        return !disabledPricingVariables.contains(id)
    }

    public mutating func setPricingVariable(_ id: String, enabled: Bool) {
        if id == "caseVolume" {
            caseVolumeRewardEnabled = enabled
            return
        }
        if enabled {
            disabledPricingVariables.removeAll { $0 == id }
        } else if !disabledPricingVariables.contains(id) {
            disabledPricingVariables.append(id)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(granularity, forKey: .granularity)
        try c.encode(administratorApproveShifts, forKey: .administratorApproveShifts)
        try c.encode(cancellationPenaltyScale, forKey: .cancellationPenaltyScale)
        try c.encode(tradePenaltyScale, forKey: .tradePenaltyScale)
        try c.encode(cancelWindowHours, forKey: .cancelWindowHours)
        try c.encode(tradeWindowHours, forKey: .tradeWindowHours)
        try c.encode(basePenaltyAmount, forKey: .basePenaltyAmount)
        try c.encode(tradePenaltiesEnabled, forKey: .tradePenaltiesEnabled)
        try c.encode(tradePenaltyAmount, forKey: .tradePenaltyAmount)
        try c.encode(tradePenaltyHoursBeforeStart, forKey: .tradePenaltyHoursBeforeStart)
        try c.encode(specialtyBaseRates, forKey: .specialtyBaseRates)
        try c.encode(doctorBaseRates, forKey: .doctorBaseRates)
        try c.encode(useAlgorithmPricingByDefault, forKey: .useAlgorithmPricingByDefault)
        try c.encode(specialtyUsesAlgorithm, forKey: .specialtyUsesAlgorithm)
        try c.encode(disabledPricingVariables, forKey: .disabledPricingVariables)
        try c.encode(caseVolumeRewardEnabled, forKey: .caseVolumeRewardEnabled)
        try c.encode(caseVolumeRewardScale, forKey: .caseVolumeRewardScale)
        try c.encode(caseVolumeRewardAuto, forKey: .caseVolumeRewardAuto)
        try c.encode(defaultDailyTokens, forKey: .defaultDailyTokens)
        try c.encode(doctorTokenLimits, forKey: .doctorTokenLimits)
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
