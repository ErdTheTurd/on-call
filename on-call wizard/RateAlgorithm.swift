import Foundation

// MARK: - Rate Algorithm (public facade → OnCallPricingEngine)

public struct RateAlgorithm {
    /// Delegates to the multi-variable On-Call Wizard pricing engine.
    public static func suggestedRate(
        specialty: String,
        date: Date,
        durationHours: Int = 24,
        baseMarketRate: Double = 120,
        granularity: SchedulingPolicy.Granularity = .day,
        observables: PricingObservables = .neutral
    ) -> SuggestedRate {
        OnCallPricingEngine.compute(
            specialty: specialty,
            date: date,
            durationHours: durationHours,
            baseMarketRate: baseMarketRate,
            granularity: granularity,
            observables: observables
        ).toSuggestedRate()
    }

    /// Legacy entry point — maps MarketConditions into PricingObservables.
    public static func suggestedRate(
        specialty: String,
        date: Date,
        durationHours: Int = 24,
        baseMarketRate: Double = 120,
        granularity: SchedulingPolicy.Granularity = .day,
        market: MarketConditions
    ) -> SuggestedRate {
        suggestedRate(
            specialty: specialty,
            date: date,
            durationHours: durationHours,
            baseMarketRate: baseMarketRate,
            granularity: granularity,
            observables: PricingObservables.from(market: market)
        )
    }

    // Retained for backward compatibility with existing call sites.
    public enum Factors {
        public static func season(for date: Date) -> Double {
            let month = Calendar.current.component(.month, from: date)
            switch month {
            case 11, 12, 1, 2: return 1.12
            case 6, 7, 8:      return 1.08
            default:           return 1.00
            }
        }

        public static func scarcity(openShifts: Int, availableDoctors: Int) -> Double {
            OnCallPricingEngine.scarcity(openShifts: openShifts, availableDoctors: availableDoctors)
        }

        public static func fillPerformance(recentFillRate: Double?) -> Double {
            OnCallPricingEngine.fillPerformance(recentFillRate: recentFillRate)
        }

        public static func leadTime(daysUntilShift: Double?) -> Double {
            OnCallPricingEngine.leadTime(daysUntilShift: daysUntilShift)
        }
    }
}

// MARK: - Market Conditions (legacy bridge type)

public struct MarketConditions: Sendable, Equatable {
    public var openShiftCount: Int
    public var availableDoctorCount: Int
    public var recentFillRate: Double?
    public var daysUntilShift: Double?

    public init(
        openShiftCount: Int = 0,
        availableDoctorCount: Int = 0,
        recentFillRate: Double? = nil,
        daysUntilShift: Double? = nil
    ) {
        self.openShiftCount = openShiftCount
        self.availableDoctorCount = availableDoctorCount
        self.recentFillRate = recentFillRate
        self.daysUntilShift = daysUntilShift
    }

    public static let neutral = MarketConditions()
}

// MARK: - Output Types

public struct SuggestedRate {
    public let floor: Double
    public let breakdown: RateBreakdown

    public var peakRate: Double {
        breakdown.peakRate ?? (breakdown.granularity == .day ? floor * 2.0 : floor * 2.2)
    }
}

public struct RateBreakdown {
    public let baseRate: Double
    public let specialtyMultiplier: Double
    public let dayOfWeekMultiplier: Double
    public let seasonMultiplier: Double
    public let holidayMultiplier: Double
    public let fillFactor: Double
    public let durationFactor: Double
    public let scarcityMultiplier: Double
    public let leadTimeMultiplier: Double
    public let suggestedFloor: Double
    public let holidayName: String?
    public let granularity: SchedulingPolicy.Granularity
    public let allComponents: [PricingFactorComponent]
    public let confidence: Double
    public let peakRate: Double?

    public init(
        baseRate: Double, specialtyMultiplier: Double, dayOfWeekMultiplier: Double,
        seasonMultiplier: Double, holidayMultiplier: Double, fillFactor: Double,
        durationFactor: Double, scarcityMultiplier: Double = 1.0, leadTimeMultiplier: Double = 1.0,
        suggestedFloor: Double, holidayName: String?,
        granularity: SchedulingPolicy.Granularity = .day,
        allComponents: [PricingFactorComponent] = [],
        confidence: Double = 1.0,
        peakRate: Double? = nil
    ) {
        self.baseRate = baseRate
        self.specialtyMultiplier = specialtyMultiplier
        self.dayOfWeekMultiplier = dayOfWeekMultiplier
        self.seasonMultiplier = seasonMultiplier
        self.holidayMultiplier = holidayMultiplier
        self.fillFactor = fillFactor
        self.durationFactor = durationFactor
        self.scarcityMultiplier = scarcityMultiplier
        self.leadTimeMultiplier = leadTimeMultiplier
        self.suggestedFloor = suggestedFloor
        self.holidayName = holidayName
        self.granularity = granularity
        self.allComponents = allComponents
        self.confidence = confidence
        self.peakRate = peakRate
    }

    public var compositeMultiplier: Double {
        specialtyMultiplier * dayOfWeekMultiplier * seasonMultiplier * holidayMultiplier
            * fillFactor * durationFactor * scarcityMultiplier * leadTimeMultiplier
    }

    /// Full decomposed factor list (20+ when using OnCallPricingEngine).
    public var factors: [(label: String, value: String, impact: Double)] {
        if !allComponents.isEmpty {
            return allComponents
                .filter { $0.weight > 0 || $0.id == "base" }
                .map { ($0.label, $0.displayValue, $0.impact) }
        }
        let unit = granularity == .day ? "/day" : "/hr"
        var items: [(String, String, Double)] = [
            ("Base market rate", "\(NumberFormat.currency(baseRate))\(unit)", 0),
            ("Specialty demand", String(format: "×%.2f", specialtyMultiplier), specialtyMultiplier - 1),
            ("Day of week", String(format: "×%.2f", dayOfWeekMultiplier), dayOfWeekMultiplier - 1),
            ("Season", String(format: "×%.2f", seasonMultiplier), seasonMultiplier - 1),
            ("Duration", String(format: "×%.2f", durationFactor), durationFactor - 1),
        ]
        if abs(scarcityMultiplier - 1.0) >= 0.01 {
            items.append(("Supply & demand", String(format: "×%.2f", scarcityMultiplier), scarcityMultiplier - 1))
        }
        if abs(fillFactor - 1.0) >= 0.01 {
            items.append(("Fill history", String(format: "×%.2f", fillFactor), fillFactor - 1))
        }
        if abs(leadTimeMultiplier - 1.0) >= 0.01 {
            items.append(("Lead time", String(format: "×%.2f", leadTimeMultiplier), leadTimeMultiplier - 1))
        }
        if holidayMultiplier > 1.0 {
            items.append(("\(holidayName ?? "Holiday") premium", String(format: "+%.0f%%", (holidayMultiplier - 1) * 100), holidayMultiplier - 1))
        }
        return items
    }

    public var variableCount: Int { max(allComponents.count, factors.count) }
}
