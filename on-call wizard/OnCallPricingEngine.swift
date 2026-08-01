import Foundation

// MARK: - On-Call Wizard Dynamic Pricing Engine
//
// Multi-phase, multi-variable pricing system for hospital on-call coverage.
// Combines static calendar tensors, live market observables, behavioral signals,
// nonlinear interaction mesh, and confidence-weighted prior blending.

/// Live + derived observables feeding the pricing engine (25+ input signals).
public struct PricingObservables: Sendable, Equatable {
    // Market supply/demand
    public var openShiftCount: Int = 0
    public var availableDoctorCount: Int = 0
    public var hospitalWideOpenShifts: Int = 0
    public var hospitalWideRosterSize: Int = 0
    public var recentFillRate: Double?
    public var daysUntilShift: Double?
    public var pendingTokenRequests: Int = 0
    public var autoApprovedDoctorCount: Int = 0
    public var adjacentUnfilledDays: Int = 0
    public var avgFillHours: Double?
    public var pendingTradeCount: Int = 0
    public var recentCancelCount: Int = 0
    public var sampleSize: Int = 0

    public static let neutral = PricingObservables()
}

/// A single priced factor surfaced in hospital UI / audit trail.
public struct PricingFactorComponent: Identifiable, Hashable, Sendable {
    public let id: String
    public let category: String
    public let label: String
    public let displayValue: String
    public let multiplier: Double
    public let weight: Double

    public var impact: Double { (multiplier - 1.0) * weight }
}

/// Full pricing output including decomposed factor mesh.
public struct PricingResult: Sendable {
    public let floor: Double
    public let peakRate: Double
    public let confidence: Double
    public let priorFloor: Double
    public let components: [PricingFactorComponent]
    public let holidayName: String?
    public let granularity: SchedulingPolicy.Granularity

    public var factorCount: Int { components.count }

    public func toSuggestedRate() -> SuggestedRate {
        let breakdown = RateBreakdown.from(pricingResult: self)
        return SuggestedRate(floor: floor, breakdown: breakdown)
    }
}

public enum OnCallPricingEngine {

    // MARK: - Public API

    public static func compute(
        specialty: String,
        date: Date,
        durationHours: Int = 24,
        baseMarketRate: Double = 120,
        granularity: SchedulingPolicy.Granularity = .day,
        observables: PricingObservables = .neutral
    ) -> PricingResult {
        let cal = Calendar.current
        let day = date.onlyDate()
        let weekday = cal.component(.weekday, from: day)
        let month = cal.component(.month, from: day)
        let dayOfMonth = cal.component(.day, from: day)
        let daysInMonth = cal.range(of: .day, in: .month, for: day)?.count ?? 30
        let quarter = (month - 1) / 3 + 1

        var components: [PricingFactorComponent] = []

        func factor(
            _ id: String, _ category: String, _ label: String,
            _ mult: Double, _ weight: Double = 1.0,
            display: String? = nil
        ) {
            components.append(PricingFactorComponent(
                id: id,
                category: category,
                label: label,
                displayValue: display ?? String(format: "×%.3f", mult),
                multiplier: mult,
                weight: weight
            ))
        }

        // ── Phase 1: Static contextual tensor (9 variables) ─────────────────
        let base = granularity == .day ? baseMarketRate * 10 : baseMarketRate
        factor("base", "Context", "Base market rate", 1.0, 0, display: "$\(Int(base))\(granularity == .day ? "/day" : "/hr")")

        let specialtyMult = specialtyDemandIndex(specialty)
        factor("specialty", "Context", "Specialty demand index", specialtyMult, 1.0)

        let dowMult = dayOfWeekIndex(weekday)
        factor("dow", "Context", "Day-of-week index", dowMult, 1.0)

        let seasonMult = seasonIndex(month: month)
        factor("season", "Context", "Seasonal index", seasonMult, 1.0)

        let holiday = HolidayCalendar.holiday(on: day)
        let holidayMult = 1.0 + (holiday?.premium ?? 0)
        if holidayMult > 1.001 {
            factor("holiday", "Context", "\(holiday?.name ?? "Holiday") premium", holidayMult, 1.0,
                   display: String(format: "+%.0f%%", (holidayMult - 1) * 100))
        }

        let quarterMult = quarterIndex(quarter)
        factor("quarter", "Context", "Quarter index", quarterMult, 0.85)

        let monthPosMult = monthPositionIndex(day: dayOfMonth, daysInMonth: daysInMonth)
        factor("monthPos", "Context", "Month-position index", monthPosMult, 0.75)

        let weekendAdjMult = weekendAdjacencyIndex(weekday: weekday)
        factor("weekendAdj", "Context", "Weekend adjacency", weekendAdjMult, 0.9)

        let durationMult = durationIndex(hours: durationHours)
        factor("duration", "Context", "Shift duration", durationMult, 0.8)

        // ── Phase 2: Dynamic market observables (11 variables) ────────────────
        let scarcityMult = scarcity(openShifts: observables.openShiftCount, availableDoctors: observables.availableDoctorCount)
        factor("scarcity", "Market", "Supply / demand scarcity", scarcityMult, 1.0)

        let fillMult = fillHistoryIndex(rate: observables.recentFillRate)
        factor("fillHist", "Market", "Historical fill rate", fillMult, 0.95)

        let leadMult = leadTimeIndex(days: observables.daysUntilShift)
        factor("leadTime", "Market", "Lead-time urgency", leadMult, 1.0)

        let loadMult = hospitalLoadIndex(
            open: observables.hospitalWideOpenShifts,
            roster: max(1, observables.hospitalWideRosterSize)
        )
        factor("hospLoad", "Market", "Hospital-wide open load", loadMult, 0.9)

        let tokenMult = tokenDemandIndex(pending: observables.pendingTokenRequests)
        factor("tokens", "Market", "Pending token demand", tokenMult, 0.85)

        let depthMult = rosterDepthIndex(
            doctors: observables.availableDoctorCount,
            open: max(1, observables.openShiftCount)
        )
        factor("rosterDepth", "Market", "Roster depth ratio", depthMult, 0.8)

        let autoMult = autoApproveIndex(count: observables.autoApprovedDoctorCount, roster: observables.availableDoctorCount)
        factor("autoPipe", "Market", "Auto-approve pipeline", autoMult, 0.7)

        let adjacentMult = adjacentGapIndex(unfilledDays: observables.adjacentUnfilledDays)
        factor("adjGap", "Market", "Adjacent coverage gaps", adjacentMult, 0.85)

        let fillTimeMult = avgFillTimeIndex(hours: observables.avgFillHours)
        factor("fillTime", "Market", "Avg time-to-fill", fillTimeMult, 0.75)

        let tradeMult = tradeFrictionIndex(pending: observables.pendingTradeCount)
        factor("trades", "Market", "Trade friction", tradeMult, 0.65)

        let cancelMult = cancelRiskIndex(recent: observables.recentCancelCount)
        factor("cancelRisk", "Market", "Cancellation risk", cancelMult, 0.7)

        // ── Phase 3: Nonlinear interaction mesh (3 cross-terms) ─────────────
        let sxw = specialtyWeekendInteraction(specialtyMult: specialtyMult, weekday: weekday)
        factor("sxw", "Interaction", "Specialty × weekend", sxw, 0.9)

        let hxs = holidayScarcityInteraction(holidayMult: holidayMult, scarcityMult: scarcityMult)
        if hxs > 1.001 {
            factor("hxs", "Interaction", "Holiday × scarcity", hxs, 0.95)
        }

        let lxs = leadScarcityInteraction(leadMult: leadMult, scarcityMult: scarcityMult)
        factor("lxs", "Interaction", "Lead-time × scarcity", lxs, 0.9)

        // ── Phase 4: Confidence-weighted prior blend (2 meta variables) ───────
        let confidence = dataConfidence(sampleSize: observables.sampleSize)
        factor("confidence", "Meta", "Data confidence", 1.0, 0, display: String(format: "%.0f%%", confidence * 100))

        let priorFloor = priorRate(base: base, specialty: specialty, granularity: granularity)
        factor("prior", "Meta", "Prior anchor rate", 1.0, 0, display: "$\(Int(priorFloor))")

        // Weighted composite product (excluding base + meta display rows)
        let priced = components.filter { $0.weight > 0 && $0.id != "base" }
        var weightedLogSum = 0.0
        var totalWeight = 0.0
        for c in priced {
            weightedLogSum += log(max(0.01, c.multiplier)) * c.weight
            totalWeight += c.weight
        }
        let meshMultiplier = exp(weightedLogSum / max(0.001, totalWeight))

        var rawFloor = base * meshMultiplier
        rawFloor = confidence * rawFloor + (1.0 - confidence) * priorFloor
        let quantized = quantize(rawFloor, granularity: granularity)
        let peak = granularity == .day ? quantized * 2.0 : quantized * 2.2

        return PricingResult(
            floor: quantized,
            peakRate: peak,
            confidence: confidence,
            priorFloor: priorFloor,
            components: components,
            holidayName: holiday?.name,
            granularity: granularity
        )
    }

    // MARK: - Phase 1 indices

    private static func specialtyDemandIndex(_ specialty: String) -> Double {
        specialtyDemandTable[specialty] ?? 1.0
    }

    private static func dayOfWeekIndex(_ weekday: Int) -> Double {
        dayOfWeekTable[weekday] ?? 1.0
    }

    private static func seasonIndex(month: Int) -> Double {
        switch month {
        case 11, 12, 1, 2: return 1.12
        case 6, 7, 8:      return 1.08
        default:           return 1.00
        }
    }

    private static func quarterIndex(_ quarter: Int) -> Double {
        switch quarter {
        case 1: return 1.06  // flu tail + winter
        case 2: return 1.00
        case 3: return 1.04  // vacation coverage
        case 4: return 1.08  // holiday season ramp
        default: return 1.0
        }
    }

    private static func monthPositionIndex(day: Int, daysInMonth: Int) -> Double {
        let fromEnd = daysInMonth - day
        if fromEnd <= 2 { return 1.05 }   // month-end crunch
        if day <= 3 { return 1.03 }       // month-start handoff
        return 1.0
    }

    private static func weekendAdjacencyIndex(weekday: Int) -> Double {
        switch weekday {
        case 6: return 1.04   // Friday before weekend
        case 1: return 1.06   // Sunday
        case 2: return 1.03   // Monday after weekend
        default: return 1.0
        }
    }

    private static func durationIndex(hours: Int) -> Double {
        if hours <= 8 { return 1.08 }
        if hours >= 24 { return 0.96 }
        return 1.0
    }

    // MARK: - Phase 2 indices

    static func scarcity(openShifts: Int, availableDoctors: Int) -> Double {
        let demand = Double(max(0, openShifts)) + 1.0
        let supply = Double(max(0, availableDoctors)) + 1.0
        let raw = pow(demand / supply, 0.35)
        return min(1.30, max(0.85, raw))
    }

    private static func fillHistoryIndex(rate: Double?) -> Double {
        fillPerformance(recentFillRate: rate)
    }

    static func fillPerformance(recentFillRate: Double?) -> Double {
        guard let rate = recentFillRate else { return 1.0 }
        switch rate {
        case ..<0.40: return 1.18
        case ..<0.60: return 1.10
        case ..<0.80: return 1.02
        case ..<0.95: return 0.98
        default:      return 0.94
        }
    }

    private static func leadTimeIndex(days: Double?) -> Double {
        leadTime(daysUntilShift: days)
    }

    static func leadTime(daysUntilShift: Double?) -> Double {
        guard let days = daysUntilShift else { return 1.0 }
        switch days {
        case ..<1:  return 1.25
        case ..<3:  return 1.15
        case ..<7:  return 1.06
        case ..<14: return 1.00
        default:    return 0.97
        }
    }

    private static func hospitalLoadIndex(open: Int, roster: Int) -> Double {
        let ratio = Double(max(0, open)) / Double(max(1, roster))
        return min(1.20, max(0.92, 1.0 + ratio * 0.08))
    }

    private static func tokenDemandIndex(pending: Int) -> Double {
        switch pending {
        case 0: return 1.0
        case 1: return 1.03
        case 2: return 1.06
        default: return min(1.15, 1.0 + Double(pending) * 0.04)
        }
    }

    private static func rosterDepthIndex(doctors: Int, open: Int) -> Double {
        let depth = Double(max(0, doctors)) / Double(open)
        if depth >= 3 { return 0.94 }
        if depth >= 1.5 { return 0.98 }
        if depth >= 0.75 { return 1.02 }
        return 1.10
    }

    private static func autoApproveIndex(count: Int, roster: Int) -> Double {
        guard roster > 0 else { return 1.0 }
        let ratio = Double(count) / Double(roster)
        return max(0.96, 1.0 - ratio * 0.06)
    }

    private static func adjacentGapIndex(unfilledDays: Int) -> Double {
        switch unfilledDays {
        case 0: return 1.0
        case 1: return 1.04
        case 2: return 1.07
        default: return min(1.14, 1.0 + Double(unfilledDays) * 0.035)
        }
    }

    private static func avgFillTimeIndex(hours: Double?) -> Double {
        guard let h = hours else { return 1.0 }
        if h > 72 { return 1.12 }
        if h > 48 { return 1.06 }
        if h < 12 { return 0.97 }
        return 1.0
    }

    private static func tradeFrictionIndex(pending: Int) -> Double {
        min(1.10, 1.0 + Double(pending) * 0.02)
    }

    private static func cancelRiskIndex(recent: Int) -> Double {
        min(1.12, 1.0 + Double(recent) * 0.015)
    }

    // MARK: - Phase 3 interactions

    private static func specialtyWeekendInteraction(specialtyMult: Double, weekday: Int) -> Double {
        let isWeekend = weekday == 1 || weekday == 7
        guard isWeekend else { return 1.0 }
        let premium = max(0, specialtyMult - 1.0) * 0.35
        return 1.0 + premium
    }

    private static func holidayScarcityInteraction(holidayMult: Double, scarcityMult: Double) -> Double {
        guard holidayMult > 1.001 else { return 1.0 }
        let h = holidayMult - 1.0
        let s = max(0, scarcityMult - 1.0)
        return 1.0 + h * s * 0.5
    }

    private static func leadScarcityInteraction(leadMult: Double, scarcityMult: Double) -> Double {
        let l = max(0, leadMult - 1.0)
        let s = max(0, scarcityMult - 1.0)
        return 1.0 + l * s * 0.4
    }

    // MARK: - Phase 4 meta

    private static func dataConfidence(sampleSize: Int) -> Double {
        // Sigmoid confidence: more historical samples → trust observables over prior.
        let x = Double(sampleSize)
        return min(0.95, max(0.35, 1.0 - exp(-x / 12.0)))
    }

    private static func priorRate(base: Double, specialty: String, granularity: SchedulingPolicy.Granularity) -> Double {
        let spec = specialtyDemandIndex(specialty)
        return quantize(base * spec * 0.98, granularity: granularity)
    }

    private static func quantize(_ value: Double, granularity: SchedulingPolicy.Granularity) -> Double {
        let step: Double = granularity == .day ? 25 : 5
        return (value / step).rounded() * step
    }

    static let specialtyDemandTable: [String: Double] = [
        "Emergency Medicine": 1.30,
        "Anesthesiology":     1.35,
        "Surgery":            1.30,
        "Orthopedics":        1.28,
        "Ob/Gyn":             1.25,
        "ENT":                1.22,
        "Neurology":          1.25,
        "Cardiology":         1.25,
        "Radiology":          1.20,
        "Psychiatry":         1.20,
        "Internal Medicine":  1.10,
        "Hospitalist":        1.05,
        "Pediatrics":         1.10,
    ]

    static let dayOfWeekTable: [Int: Double] = [
        1: 1.15, 2: 1.00, 3: 1.00, 4: 1.00, 5: 1.00, 6: 1.05, 7: 1.20,
    ]
}

extension RateBreakdown {
    static func from(pricingResult: PricingResult) -> RateBreakdown {
        func mult(_ id: String) -> Double {
            pricingResult.components.first { $0.id == id }?.multiplier ?? 1.0
        }
        return RateBreakdown(
            baseRate: pricingResult.priorFloor,
            specialtyMultiplier: mult("specialty"),
            dayOfWeekMultiplier: mult("dow"),
            seasonMultiplier: mult("season"),
            holidayMultiplier: mult("holiday"),
            fillFactor: mult("fillHist"),
            durationFactor: mult("duration"),
            scarcityMultiplier: mult("scarcity"),
            leadTimeMultiplier: mult("leadTime"),
            suggestedFloor: pricingResult.floor,
            holidayName: pricingResult.holidayName,
            granularity: pricingResult.granularity,
            allComponents: pricingResult.components,
            confidence: pricingResult.confidence,
            peakRate: pricingResult.peakRate
        )
    }
}
