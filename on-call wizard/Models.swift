import Foundation

// VerificationStatus lives in SharedTypes.swift

// MARK: - Rate Escalation

public enum EscalationMode: Hashable {
    case automatic
    case flat(Double)

    public func currentRate(floor: Double, hoursUntilShift: Double, perDay: Bool = true) -> Double {
        switch self {
        case .automatic:
            if perDay {
                return floor * EscalationCurve.multiplier(forDays: hoursUntilShift / 24)
            }
            return floor * EscalationCurve.multiplier(forHours: hoursUntilShift)
        case .flat(let rate):    return max(floor, rate)
        }
    }
}

extension EscalationMode: Codable {
    private enum CodingKeys: String, CodingKey { case type, rate }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        if type == "flat" {
            let rate = try c.decode(Double.self, forKey: .rate)
            self = .flat(rate)
        } else {
            self = .automatic
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .automatic:
            try c.encode("automatic", forKey: .type)
        case .flat(let rate):
            try c.encode("flat", forKey: .type)
            try c.encode(rate, forKey: .rate)
        }
    }
}

public struct EscalationCurve {
    private static let hourBreakpoints: [(Double, Double)] = [
        (72, 1.00), (48, 1.15), (24, 1.35), (12, 1.60), (6, 1.85), (2, 2.20), (0, 2.20),
    ]
    private static let dayBreakpoints: [(Double, Double)] = [
        (30, 1.00), (14, 1.10), (7, 1.20), (3, 1.35), (1, 1.60), (0, 2.00),
    ]

    public static func multiplier(forHours hours: Double) -> Double { interpolate(hours, breakpoints: hourBreakpoints) }
    public static func multiplier(forDays days: Double) -> Double { interpolate(days, breakpoints: dayBreakpoints) }

    private static func interpolate(_ value: Double, breakpoints: [(Double, Double)]) -> Double {
        guard value > 0 else { return breakpoints.last!.1 }
        for i in 0..<(breakpoints.count - 1) {
            let (h1, m1) = breakpoints[i]
            let (h2, m2) = breakpoints[i + 1]
            if value <= h1 && value >= h2 {
                let t = (h1 - value) / (h1 - h2)
                return m1 + (m2 - m1) * t
            }
        }
        return breakpoints[0].1
    }

    public static func urgencyTier(hoursUntilShift: Double, perDay: Bool = true) -> UrgencyTier {
        if perDay {
            let days = hoursUntilShift / 24
            switch days {
            case ..<0: return .past
            case 0..<1: return .critical
            case 1..<3: return .high
            case 3..<7: return .moderate
            default: return .low
            }
        }
        switch hoursUntilShift {
        case ..<0: return .past
        case 0..<12: return .critical
        case 12..<24: return .high
        case 24..<48: return .moderate
        default: return .low
        }
    }
}

public enum UrgencyTier {
    case past, low, moderate, high, critical

    public var label: String {
        switch self {
        case .past:     return "Past"
        case .low:      return "Low"
        case .moderate: return "Moderate"
        case .high:     return "High"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Shift

public enum RateUnit: String, Codable, Hashable {
    case perDay  = "per day"
    case perHour = "per hour"
}

public struct Shift: Identifiable, Hashable, Codable {
    public let id: UUID
    public let hospitalID: UUID
    public let hospital: String
    public let specialty: String
    public let start: Date
    public let durationHours: Int
    public let rateFloor: Double
    public let rateUnit: RateUnit
    public let escalationMode: EscalationMode
    public let escalationIntervalHours: Int
    public var usesAlgorithmPricing: Bool

    private enum CodingKeys: String, CodingKey {
        case id, hospitalID, hospital, specialty, start, durationHours
        case rateFloor, rateUnit, escalationMode, escalationIntervalHours, usesAlgorithmPricing
    }

    public init(
        id: UUID = UUID(),
        hospitalID: UUID = UUID(),
        hospital: String,
        specialty: String,
        start: Date,
        durationHours: Int = 24,
        rateFloor: Double,
        rateUnit: RateUnit = .perDay,
        escalationMode: EscalationMode = .automatic,
        escalationIntervalHours: Int = 24,
        usesAlgorithmPricing: Bool = true
    ) {
        self.id = id
        self.hospitalID = hospitalID
        self.hospital = hospital
        self.specialty = specialty
        self.start = rateUnit == .perDay ? Calendar.current.startOfDay(for: start) : start
        self.durationHours = durationHours
        self.rateFloor = rateFloor
        self.rateUnit = rateUnit
        self.escalationMode = escalationMode
        self.escalationIntervalHours = escalationIntervalHours
        self.usesAlgorithmPricing = usesAlgorithmPricing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        hospitalID = try c.decode(UUID.self, forKey: .hospitalID)
        hospital = try c.decode(String.self, forKey: .hospital)
        specialty = try c.decode(String.self, forKey: .specialty)
        start = try c.decode(Date.self, forKey: .start)
        durationHours = try c.decode(Int.self, forKey: .durationHours)
        rateFloor = try c.decode(Double.self, forKey: .rateFloor)
        rateUnit = try c.decode(RateUnit.self, forKey: .rateUnit)
        escalationMode = try c.decode(EscalationMode.self, forKey: .escalationMode)
        escalationIntervalHours = try c.decodeIfPresent(Int.self, forKey: .escalationIntervalHours) ?? 24
        usesAlgorithmPricing = try c.decodeIfPresent(Bool.self, forKey: .usesAlgorithmPricing) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(hospitalID, forKey: .hospitalID)
        try c.encode(hospital, forKey: .hospital)
        try c.encode(specialty, forKey: .specialty)
        try c.encode(start, forKey: .start)
        try c.encode(durationHours, forKey: .durationHours)
        try c.encode(rateFloor, forKey: .rateFloor)
        try c.encode(rateUnit, forKey: .rateUnit)
        try c.encode(escalationMode, forKey: .escalationMode)
        try c.encode(escalationIntervalHours, forKey: .escalationIntervalHours)
        try c.encode(usesAlgorithmPricing, forKey: .usesAlgorithmPricing)
    }

    /// Convenience init using call date (per-day default).
    public init(
        hospitalID: UUID = UUID(),
        hospital: String,
        specialty: String,
        date: Date,
        rateFloor: Double,
        escalationMode: EscalationMode = .automatic,
        escalationIntervalHours: Int = 24
    ) {
        self.init(
            hospitalID: hospitalID, hospital: hospital, specialty: specialty,
            start: date, durationHours: 24, rateFloor: rateFloor,
            rateUnit: .perDay, escalationMode: escalationMode,
            escalationIntervalHours: escalationIntervalHours
        )
    }

    public var date: Date { Calendar.current.startOfDay(for: start) }
    public var granularity: SchedulingPolicy.Granularity { rateUnit == .perDay ? .day : .hour }
    public var daysUntilStart: Double { hoursUntilStart / 24 }

    public var hoursUntilStart: Double {
        max(0, start.timeIntervalSinceNow / 3_600)
    }

    public var isPast: Bool { Date() >= end }

    public var currentRate: Double {
        escalationMode.currentRate(floor: rateFloor, hoursUntilShift: hoursUntilStart, perDay: rateUnit == .perDay)
    }

    public var rateUnitLabel: String { rateUnit == .perDay ? "/day" : "/hr" }
    public var durationLabel: String { rateUnit == .perDay ? "Full day" : "\(durationHours)h" }

    public var displayDateLabel: String {
        if rateUnit == .perHour {
            return "\(date.formatted(.dateTime.month(.abbreviated).day())) · \(start.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    public var rateDisplay: String { "$\(Int(currentRate))\(rateUnitLabel)" }

    public var urgencyTier: UrgencyTier {
        isPast ? .past : EscalationCurve.urgencyTier(hoursUntilShift: hoursUntilStart, perDay: rateUnit == .perDay)
    }

    public var end: Date {
        rateUnit == .perDay
            ? Calendar.current.date(byAdding: .day, value: 1, to: date) ?? start.addingTimeInterval(86_400)
            : start.addingTimeInterval(Double(durationHours) * 3_600)
    }

    public var isActive: Bool { Date() >= start && Date() < end }
    public var totalEarnings: Double { rateUnit == .perDay ? currentRate : currentRate * Double(durationHours) }

    /// Escalated rate as of a reference date (e.g. assignment / approval time).
    public func rate(asOf referenceDate: Date) -> Double {
        let hours = max(0, start.timeIntervalSince(referenceDate) / 3_600)
        return escalationMode.currentRate(floor: rateFloor, hoursUntilShift: hours, perDay: rateUnit == .perDay)
    }

    public func toDoctorShift(doctorID: UUID, payRate: Decimal? = nil) -> DoctorShift {
        DoctorShift(
            id: id, hospitalID: hospitalID, doctorID: doctorID,
            date: date,
            startTime: rateUnit == .perHour ? start : nil,
            endTime: rateUnit == .perHour ? end : nil,
            status: .scheduled,
            payRate: payRate ?? Decimal(totalEarnings)
        )
    }
}

// MARK: - Doctor Profile

public struct DoctorProfile: Codable {
    public var id: UUID
    public var userID: UUID?
    public var firstName: String
    public var lastName: String
    public var credential: CredentialType
    public var npi: String
    public var deaNumber: String
    public var licenseNumber: String
    public var licenseState: String
    public var specialties: [String]
    public var email: String
    public var verificationStatus: VerificationStatus
    public var verificationFlags: [String]
    public var npiRegistryName: String?
    public var npiTaxonomy: String?

    public init(
        id: UUID = UUID(),
        userID: UUID? = nil,
        firstName: String, lastName: String, credential: CredentialType,
        npi: String, deaNumber: String = "",
        licenseNumber: String, licenseState: String,
        specialties: [String], email: String,
        verificationStatus: VerificationStatus = .unverified,
        verificationFlags: [String] = [],
        npiRegistryName: String? = nil, npiTaxonomy: String? = nil
    ) {
        self.id = id; self.userID = userID
        self.firstName = firstName; self.lastName = lastName; self.credential = credential
        self.npi = npi; self.deaNumber = deaNumber; self.licenseNumber = licenseNumber; self.licenseState = licenseState
        self.specialties = specialties; self.email = email
        self.verificationStatus = verificationStatus; self.verificationFlags = verificationFlags
        self.npiRegistryName = npiRegistryName; self.npiTaxonomy = npiTaxonomy
    }

    public enum CredentialType: String, Codable, CaseIterable, Identifiable {
        case md = "MD"; case doct = "DO"; case np = "NP"; case pa = "PA"
        public var id: String { rawValue }
    }

    public var displayName: String { "\(firstName) \(lastName), \(credential.rawValue)" }
    public static let storageKey = "doctor_profile_v2"

    public static func load() -> DoctorProfile? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let p = try? JSONDecoder().decode(DoctorProfile.self, from: data) else { return nil }
        return p
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: DoctorProfile.storageKey)
        }
    }
}

// MARK: - Hospital Profile

public struct HospitalProfile: Codable {
    public var id: UUID
    public var userID: UUID?
    public var name: String
    public var npi: String
    public var email: String
    public var verificationStatus: VerificationStatus
    public var verificationFlags: [String]
    public var npiRegistryName: String?
    public var schedulingPolicy: SchedulingPolicy

    public init(
        id: UUID = UUID(),
        userID: UUID? = nil,
        name: String, npi: String, email: String,
        verificationStatus: VerificationStatus,
        verificationFlags: [String],
        npiRegistryName: String? = nil,
        schedulingPolicy: SchedulingPolicy = SchedulingPolicy()
    ) {
        self.id = id; self.userID = userID; self.name = name; self.npi = npi; self.email = email
        self.verificationStatus = verificationStatus; self.verificationFlags = verificationFlags
        self.npiRegistryName = npiRegistryName; self.schedulingPolicy = schedulingPolicy
    }

    public static let storageKey = "hospital_profile_v2"

    public static func load() -> HospitalProfile? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let p = try? JSONDecoder().decode(HospitalProfile.self, from: data) else { return nil }
        return p
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: HospitalProfile.storageKey)
        }
    }
}

// MARK: - Doctor Summary

public struct DoctorSummary: Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let credential: String
    public let specialty: String
    public var npi: String
    public var isAutoApproved: Bool
    public var verificationStatus: VerificationStatus

    public init(id: UUID = UUID(), name: String, credential: String, specialty: String,
                npi: String = "",
                isAutoApproved: Bool = false, verificationStatus: VerificationStatus = .verified) {
        self.id = id; self.name = name; self.credential = credential
        self.specialty = specialty; self.npi = npi
        self.isAutoApproved = isAutoApproved
        self.verificationStatus = verificationStatus
    }
}

// MARK: - Demo Data

public enum DemoData {
    public static let specialties = [
        "Internal Medicine",
        "Orthopedics",
        "Ob/Gyn",
        "ENT",
        "Emergency Medicine",
        "Anesthesiology",
        "Radiology",
        "Surgery",
        "Pediatrics",
        "Psychiatry",
        "Cardiology",
        "Neurology",
        "Hospitalist",
    ]

    /// Doctor calendar: past days dim; future = urgency from real open shifts.
    public static func doctorCalendarData(
        for month: Date,
        shifts: [Shift],
        assignments: AssignedShiftsStore,
        unavailable: UnavailableDaysStore,
        currentDoctorID: UUID
    ) -> [CalendarHeatmap.DayData] {
        let cal = Calendar.current
        let start = month.startOfMonth()
        guard let range = cal.range(of: .day, in: .month, for: start) else { return [] }
        let today = cal.startOfDay(for: Date())

        return range.compactMap { offset -> CalendarHeatmap.DayData? in
            guard let date = cal.date(byAdding: .day, value: offset - 1, to: start) else { return nil }
            let isPast = date < today
            let dayShifts = shifts.filter { cal.isDate($0.date, inSameDayAs: date) }
            let hospitalIDs = Array(Set(dayShifts.map(\.hospitalID)))
            let fallbackHospitalID = HospitalProfile.load()?.id
            let isUnavailable = unavailable.isBlockedOnAnyHospital(
                date,
                hospitalIDs: hospitalIDs.isEmpty ? (fallbackHospitalID.map { [$0] } ?? []) : hospitalIDs
            )
            let isFilled = assignments.isFilledByOthers(on: date, shifts: shifts, currentDoctorID: currentDoctorID)

            if isPast {
                return CalendarHeatmap.DayData(
                    date: date, urgencyValue: -1, shiftCount: dayShifts.count, isPast: true,
                    isFilledByOthers: isFilled, isHospitalUnavailable: isUnavailable
                )
            }

            let futureShifts = dayShifts.filter { !$0.isPast && !assignments.isShiftFilled($0.id) }
            let bestShift = futureShifts.min(by: { $0.hoursUntilStart < $1.hoursUntilStart })
            let urgencyValue: Double = bestShift.map { $0.hoursUntilStart } ?? 0

            return CalendarHeatmap.DayData(
                date: date, urgencyValue: urgencyValue,
                shiftCount: futureShifts.count,
                isPast: false,
                isFilledByOthers: isFilled,
                isHospitalUnavailable: isUnavailable
            )
        }
    }

    /// Hospital calendar: color = demand; includes blocked-day flags.
    public static func hospitalCalendarData(
        for month: Date,
        shifts: [Shift],
        unavailable: UnavailableDaysStore,
        hospitalID: UUID
    ) -> [CalendarHeatmap.DayData] {
        let cal = Calendar.current
        let start = month.startOfMonth()
        guard let range = cal.range(of: .day, in: .month, for: start) else { return [] }
        let today = cal.startOfDay(for: Date())

        return range.compactMap { offset -> CalendarHeatmap.DayData? in
            guard let date = cal.date(byAdding: .day, value: offset - 1, to: start) else { return nil }
            let isPast = date < today
            let dayShifts = shifts.filter { cal.isDate($0.date, inSameDayAs: date) }
            let openShifts = dayShifts.filter { !AssignedShiftsStore.shared.isShiftFilled($0.id) && !$0.isPast }
            let maxRate = openShifts.map { $0.currentRate }.max() ?? 0
            let blocked = unavailable.isBlocked(date, hospitalID: hospitalID)
            return CalendarHeatmap.DayData(
                date: date, urgencyValue: isPast ? -1 : maxRate,
                shiftCount: openShifts.count, isPast: isPast,
                isHospitalUnavailable: blocked
            )
        }
    }
}
