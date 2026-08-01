// PenaltyCalculator.swift
// Computes monetary penalties based on hospital on-call policy.

import Foundation

public enum PenaltyCalculator {
    public static func preview(
        for action: SchedulingAction,
        policy: SchedulingPolicy,
        shiftStart: Date,
        now: Date = Date(),
        baseAmountOverride: Decimal? = nil
    ) -> PolicyPreview {
        let hours = hoursUntil(start: shiftStart, from: now)
        let window = action == .cancel ? policy.cancelWindowHours : policy.tradeWindowHours

        let percent: Double
        let amount: Decimal
        switch action {
        case .cancel:
            percent = percentFor(hoursRemaining: hours, scale: policy.cancellationPenaltyScale)
            let base = baseAmountOverride ?? policy.basePenaltyAmount
            amount = (base * Decimal(percent)).rounded(2)
        case .trade:
            (percent, amount) = tradePenalty(hoursRemaining: hours, policy: policy)
        }

        return PolicyPreview(
            allowed: hours > Double(window),
            penaltyAmount: amount,
            penaltyPercent: percent,
            hoursRemaining: hours,
            windowHours: window,
            action: action
        )
    }

    public static func penaltyAmount(
        for action: SchedulingAction,
        policy: SchedulingPolicy,
        shiftStart: Date,
        now: Date = Date(),
        baseAmountOverride: Decimal? = nil
    ) -> Decimal {
        preview(for: action, policy: policy, shiftStart: shiftStart, now: now, baseAmountOverride: baseAmountOverride).penaltyAmount
    }

    public static func isActionAllowed(
        _ action: SchedulingAction,
        policy: SchedulingPolicy,
        shiftStart: Date,
        now: Date = Date()
    ) -> Bool {
        let hours = hoursUntil(start: shiftStart, from: now)
        switch action {
        case .cancel: return hours > Double(policy.cancelWindowHours)
        case .trade:  return hours > Double(policy.tradeWindowHours)
        }
    }

    private static func tradePenalty(hoursRemaining: Double, policy: SchedulingPolicy) -> (Double, Decimal) {
        guard policy.tradePenaltiesEnabled else { return (0, 0) }
        if hoursRemaining <= Double(policy.tradePenaltyHoursBeforeStart) {
            return (1.0, policy.tradePenaltyAmount.rounded(2))
        }
        return (0, 0)
    }

    private static func percentFor(hoursRemaining: Double, scale: [SchedulingPolicy.PenaltyBracket]) -> Double {
        for bracket in scale.sorted(by: { $0.hoursBeforeStart < $1.hoursBeforeStart }) {
            if hoursRemaining <= Double(bracket.hoursBeforeStart) {
                return max(1.0, min(5.0, bracket.penaltyPercent))
            }
        }
        return 1.0
    }

    private static func hoursUntil(start: Date, from now: Date) -> Double {
        max(0, start.timeIntervalSince(now) / 3600.0)
    }
}

private extension Decimal {
    func rounded(_ places: Int) -> Decimal {
        var result = Decimal()
        var value = self
        NSDecimalRound(&result, &value, places, .plain)
        return result
    }
}
