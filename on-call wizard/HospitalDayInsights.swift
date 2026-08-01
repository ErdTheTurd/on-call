import Foundation

// MARK: - Hospital day coverage models

struct HospitalDaySummary: Identifiable, Hashable {
    let date: Date
    let isBlocked: Bool
    let specialtyRows: [SpecialtyRow]

    var id: Date { date.onlyDate() }

    struct SpecialtyRow: Identifiable, Hashable {
        let id: String
        let specialty: String
        let shift: Shift?
        let onCallDoctorName: String?
        let onCallCredential: String?
        let paymentAmount: Double
        let goingRate: Double?
        let approvedRate: Double?
        let proposedRate: Double?
        let algorithmRate: Double?
        let isProposedRateCustom: Bool
        let rateUnitLabel: String
        let isFilled: Bool
        let hasShiftPosted: Bool
        let tokenRequests: [TokenSummary]
    }

    struct TokenSummary: Identifiable, Hashable {
        let id: UUID
        let doctorName: String
        let credential: String
        let status: TokenStore.TokenRequest.RequestStatus
        let requestedAt: Date
        let approvedAt: Date?
        let specialty: String
    }

    var totalPaid: Double {
        specialtyRows.filter(\.isFilled).map(\.paymentAmount).reduce(0, +)
    }

    var onCallNames: [String] {
        specialtyRows.compactMap(\.onCallDoctorName)
    }

    var pendingRequestCount: Int {
        specialtyRows.flatMap(\.tokenRequests).filter { $0.status == .pending }.count
    }

    var approvedRequestCount: Int {
        specialtyRows.flatMap(\.tokenRequests).filter { $0.status == .approved || $0.status == .autoApproved }.count
    }

    var coverageFillLevel: CalendarHeatmap.DayData.CoverageFillLevel {
        HospitalDayInsights.coverageFillLevel(for: specialtyRows)
    }

    /// Hover card ordering: partial days show open specialties first, then filled.
    var hoverOrderedRows: [SpecialtyRow] {
        switch coverageFillLevel {
        case .partial:
            let unfilled = specialtyRows.filter { $0.hasShiftPosted && !$0.isFilled }
            let filled = specialtyRows.filter(\.isFilled)
            let rest = specialtyRows.filter { !$0.hasShiftPosted && !$0.isFilled }
            return unfilled + filled + rest
        case .allFilled, .noneFilled:
            return specialtyRows
        }
    }

    var hoverUnfilledRows: [SpecialtyRow] {
        specialtyRows.filter { $0.hasShiftPosted && !$0.isFilled }
    }

    var hoverFilledRows: [SpecialtyRow] {
        specialtyRows.filter(\.isFilled)
    }

    var hoverUnpostedRows: [SpecialtyRow] {
        specialtyRows.filter { !$0.hasShiftPosted && !$0.isFilled }
    }
}

// MARK: - Builder

enum HospitalDayInsights {
    /// All specialties the hospital tracks (consistent list for every day).
    @MainActor
    static func trackedSpecialties(hospitalID: UUID) -> [String] {
        let fromShifts = Services.hospital.shifts
            .filter { $0.hospitalID == hospitalID }
            .map(\.specialty)
        let fromTokens = TokenStore.shared.requestedDays
            .filter { $0.hospitalID == hospitalID }
            .map(\.specialty)
        let fromRoster = DoctorRosterStore.shared.doctors.map(\.specialty)
        var all = Set(fromShifts + fromTokens + fromRoster)
        all.formUnion(DemoData.specialties)
        let ordered = DemoData.specialties.filter { all.contains($0) }
        let extras = all.subtracting(DemoData.specialties).sorted()
        return ordered + extras
    }

    static func coverageFillLevel(for rows: [HospitalDaySummary.SpecialtyRow]) -> CalendarHeatmap.DayData.CoverageFillLevel {
        let posted = rows.filter(\.hasShiftPosted)
        guard !posted.isEmpty else { return .noneFilled }
        let filled = posted.filter(\.isFilled).count
        if filled == posted.count { return .allFilled }
        if filled == 0 { return .noneFilled }
        return .partial
    }

    @MainActor
    static func calendarDayData(for month: Date, hospitalID: UUID) -> [CalendarHeatmap.DayData] {
        let cal = Calendar.current
        let start = month.startOfMonth()
        guard let range = cal.range(of: .day, in: .month, for: start) else { return [] }
        let today = cal.startOfDay(for: Date())
        let unavailable = UnavailableDaysStore.shared

        return range.compactMap { offset -> CalendarHeatmap.DayData? in
            guard let date = cal.date(byAdding: .day, value: offset - 1, to: start) else { return nil }
            let day = date.onlyDate()
            let isPast = day < today
            let blocked = unavailable.isBlocked(day, hospitalID: hospitalID)
            let summary = summary(for: day, hospitalID: hospitalID)
            let openCount = summary.specialtyRows.filter { $0.hasShiftPosted && !$0.isFilled }.count

            return CalendarHeatmap.DayData(
                date: day,
                urgencyValue: 0,
                shiftCount: openCount,
                isPast: isPast,
                isHospitalUnavailable: blocked,
                coverageFillLevel: blocked ? nil : summary.coverageFillLevel
            )
        }
    }

    @MainActor
    static func summary(for date: Date, hospitalID: UUID) -> HospitalDaySummary {
        let day = date.onlyDate()
        let cal = Calendar.current
        let shifts = Services.hospital.shifts.filter {
            $0.hospitalID == hospitalID && cal.isDate($0.date, inSameDayAs: day)
        }
        let tokens = TokenStore.shared.requests(forHospitalID: hospitalID, on: day)
        let blocked = UnavailableDaysStore.shared.isBlocked(day, hospitalID: hospitalID)
        let roster = DoctorRosterStore.shared.doctors
        let specialties = trackedSpecialties(hospitalID: hospitalID)

        let rows = specialties.map { specialty -> HospitalDaySummary.SpecialtyRow in
            let shift = shifts.first { $0.specialty == specialty }
            let assignment = shift.flatMap { s in
                AssignedShiftsStore.shared.assignedShifts.first {
                    $0.shift.id == s.id && $0.status != .canceled
                }
            }

            let doctorName: String?
            let credential: String?
            if let assignment {
                if let token = tokens.first(where: { $0.doctorID == assignment.doctorID && $0.specialty == specialty }) {
                    doctorName = token.doctorName
                    credential = token.credential
                } else if let doc = roster.first(where: { $0.id == assignment.doctorID }) {
                    doctorName = doc.name
                    credential = doc.credential
                } else if assignment.doctorID == SessionStore.shared.currentDoctorID,
                          let profile = SessionStore.shared.doctorProfile {
                    doctorName = "\(profile.firstName) \(profile.lastName)"
                    credential = profile.credential.rawValue
                } else {
                    doctorName = "Assigned physician"
                    credential = nil
                }
            } else {
                doctorName = nil
                credential = nil
            }

            let payment: Double
            let goingRate: Double?
            let approvedRate: Double?
            let proposedRate: Double?
            let algorithmRate: Double?
            let isProposedRateCustom: Bool
            let unitLabel: String

            if let assignment, let shift {
                let approvedToken = tokens.first {
                    $0.doctorID == assignment.doctorID &&
                    $0.specialty == specialty &&
                    ($0.status == .approved || $0.status == .autoApproved)
                }
                let locked = approvedToken?.shiftRate ?? shift.rate(asOf: assignment.assignedAt)
                approvedRate = locked
                goingRate = shift.currentRate
                unitLabel = shift.rateUnitLabel
                payment = shift.rateUnit == .perDay
                    ? locked
                    : locked * Double(shift.durationHours)
                proposedRate = nil
                algorithmRate = nil
                isProposedRateCustom = false
            } else if let shift {
                approvedRate = nil
                goingRate = shift.currentRate
                unitLabel = shift.rateUnitLabel
                payment = 0
                proposedRate = nil
                algorithmRate = nil
                isProposedRateCustom = false
            } else {
                approvedRate = nil
                goingRate = nil
                unitLabel = ProposedRateStore.shared.rateUnitLabel(for: hospitalID)
                payment = 0
                let proposal = ProposedRateStore.shared.proposedRate(
                    specialty: specialty,
                    date: day,
                    hospitalID: hospitalID
                )
                proposedRate = proposal.rate
                algorithmRate = proposal.algorithmRate
                isProposedRateCustom = proposal.isCustom
            }

            let specialtyTokens = tokens.filter { $0.specialty == specialty }.map { req in
                HospitalDaySummary.TokenSummary(
                    id: req.id,
                    doctorName: req.doctorName,
                    credential: req.credential,
                    status: req.status,
                    requestedAt: req.requestedAt,
                    approvedAt: req.approvedAt,
                    specialty: req.specialty
                )
            }

            return HospitalDaySummary.SpecialtyRow(
                id: specialty,
                specialty: specialty,
                shift: shift,
                onCallDoctorName: doctorName,
                onCallCredential: credential,
                paymentAmount: payment,
                goingRate: goingRate,
                approvedRate: approvedRate,
                proposedRate: proposedRate,
                algorithmRate: algorithmRate,
                isProposedRateCustom: isProposedRateCustom,
                rateUnitLabel: unitLabel,
                isFilled: assignment != nil,
                hasShiftPosted: shift != nil,
                tokenRequests: specialtyTokens.sorted { $0.requestedAt < $1.requestedAt }
            )
        }

        return HospitalDaySummary(date: day, isBlocked: blocked, specialtyRows: rows)
    }
}
