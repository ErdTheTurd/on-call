import Foundation
import Combine

// MARK: - Proposed rates (algorithm + per-day overrides)

@MainActor
final class ProposedRateStore: ObservableObject {
    static let shared = ProposedRateStore()

    private let storageKey = "proposed_rates_v1"
    private let doctorDayKey = "doctor_day_rates_v1"

    private struct Entry: Codable, Equatable {
        let hospitalID: UUID
        let date: Date
        let specialty: String
        var rate: Double
    }

    private struct DoctorDayEntry: Codable, Equatable {
        let hospitalID: UUID
        let date: Date
        let doctorID: UUID
        var rate: Double
    }

    @Published private var entries: [Entry] = []
    @Published private var doctorDayEntries: [DoctorDayEntry] = []

    private init() { load() }

    func algorithmRate(specialty: String, date: Date, hospitalID: UUID) -> Double {
        pricingResult(specialty: specialty, date: date, hospitalID: hospitalID).floor
    }

    func suggestedRate(specialty: String, date: Date, hospitalID: UUID) -> SuggestedRate {
        pricingResult(specialty: specialty, date: date, hospitalID: hospitalID).toSuggestedRate()
    }

    func pricingResult(specialty: String, date: Date, hospitalID: UUID) -> PricingResult {
        let policy = SchedulingPolicyStore.shared.policy(for: hospitalID)
        let algoStore = AlgorithmPresetStore.shared
        var obs = observables(specialty: specialty, date: date, hospitalID: hospitalID)
        obs.casesLast90Days = CaseVolumeInsights.casesLast90Days(hospitalID: hospitalID, specialty: specialty)

        let weekday = Calendar.current.component(.weekday, from: date.onlyDate())
        let preset = algoStore.preset(forWeekday: weekday) ?? algoStore.activePreset

        let disabled: Set<String>
        let overrides: [String: Double]
        let caseEnabled: Bool
        let caseScale: Int

        if preset.id == algoStore.activePresetID {
            // Live editing the active preset
            disabled = Set(algoStore.workingDisabled)
            overrides = algoStore.workingOverrides
            caseEnabled = policy.caseVolumeRewardEnabled
            caseScale = policy.caseVolumeRewardScale
        } else {
            disabled = Set(preset.disabledVariables)
            overrides = preset.factorOverrides
            caseEnabled = preset.caseVolumeRewardEnabled
            caseScale = preset.caseVolumeRewardScale
        }

        return OnCallPricingEngine.compute(
            specialty: specialty,
            date: date.onlyDate(),
            granularity: policy.granularity,
            observables: obs,
            disabledFactorIDs: disabled,
            factorOverrides: overrides,
            caseVolumeRewardEnabled: caseEnabled,
            caseVolumeRewardScale: caseScale
        )
    }

    func observables(specialty: String, date: Date, hospitalID: UUID) -> PricingObservables {
        let day = date.onlyDate()
        let cal = Calendar.current
        let assignments = AssignedShiftsStore.shared
        let roster = DoctorRosterStore.shared.doctors
        let tokens = TokenStore.shared

        let hospitalShifts = Services.hospital.shifts.filter { $0.hospitalID == hospitalID }
        let specialtyShifts = hospitalShifts.filter { $0.specialty == specialty }

        let openCount = specialtyShifts.filter {
            !$0.isPast && !assignments.isShiftFilled($0.id)
        }.count

        let specialtyDoctors = roster.filter {
            $0.specialty == specialty && $0.verificationStatus == .verified
        }
        let availableDoctors = specialtyDoctors.count

        let hospitalWideOpen = hospitalShifts.filter {
            !$0.isPast && !assignments.isShiftFilled($0.id)
        }.count
        let hospitalRoster = roster.filter { $0.verificationStatus == .verified }.count

        let pastShifts = specialtyShifts.filter(\.isPast)
        let recentFillRate: Double?
        if pastShifts.isEmpty {
            recentFillRate = nil
        } else {
            let filled = pastShifts.filter { assignments.isShiftFilled($0.id) }.count
            recentFillRate = Double(filled) / Double(pastShifts.count)
        }

        let today = cal.startOfDay(for: Date())
        let daysUntil = cal.dateComponents([.day], from: today, to: day).day.map(Double.init)

        let pendingTokens = tokens.requests(forHospitalID: hospitalID, on: day)
            .filter { $0.specialty == specialty && $0.status == .pending }.count

        let autoApproved = specialtyDoctors.filter(\.isAutoApproved).count

        var adjacentUnfilled = 0
        for offset in [-2, -1, 1, 2] {
            guard let adj = cal.date(byAdding: .day, value: offset, to: day) else { continue }
            let adjShifts = specialtyShifts.filter { cal.isDate($0.date, inSameDayAs: adj) && !$0.isPast }
            let anyOpen = adjShifts.contains { !assignments.isShiftFilled($0.id) }
            if anyOpen { adjacentUnfilled += 1 }
        }

        let sampleSize = pastShifts.count + specialtyShifts.count
        let asking = Self.resolveAskingPrice(
            specialty: specialty,
            date: day,
            hospitalID: hospitalID,
            specialtyShifts: specialtyShifts
        )

        return PricingObservables(
            openShiftCount: openCount,
            availableDoctorCount: availableDoctors,
            hospitalWideOpenShifts: hospitalWideOpen,
            hospitalWideRosterSize: hospitalRoster,
            recentFillRate: recentFillRate,
            daysUntilShift: daysUntil,
            pendingTokenRequests: pendingTokens,
            autoApprovedDoctorCount: autoApproved,
            adjacentUnfilledDays: adjacentUnfilled,
            avgFillHours: nil,
            pendingTradeCount: 0,
            recentCancelCount: 0,
            sampleSize: sampleSize,
            casesLast90Days: 0,
            currentAskingPrice: asking
        )
    }

    /// Posted shift rate for the day, else specialty base — never the live algo output (avoids feedback loop).
    static func resolveAskingPrice(
        specialty: String,
        date: Date,
        hospitalID: UUID,
        specialtyShifts: [Shift]? = nil
    ) -> Double? {
        let day = date.onlyDate()
        let shifts = specialtyShifts ?? Services.hospital.shifts.filter {
            $0.hospitalID == hospitalID && $0.specialty == specialty
        }
        if let posted = shifts.first(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
            return posted.rateFloor
        }
        let base = SchedulingPolicyStore.shared.policy(for: hospitalID).specialtyBaseRates[specialty]
        return base.flatMap { $0 > 0 ? $0 : nil }
    }

    /// Legacy bridge for MarketConditions call sites.
    func marketConditions(specialty: String, date: Date, hospitalID: UUID) -> MarketConditions {
        let o = observables(specialty: specialty, date: date, hospitalID: hospitalID)
        return MarketConditions(
            openShiftCount: o.openShiftCount,
            availableDoctorCount: o.availableDoctorCount,
            recentFillRate: o.recentFillRate,
            daysUntilShift: o.daysUntilShift
        )
    }

    func rateUnitLabel(for hospitalID: UUID) -> String {
        SchedulingPolicyStore.shared.policy(for: hospitalID).granularity == .hour ? "/hr" : "/day"
    }

    func proposedRate(
        specialty: String,
        date: Date,
        hospitalID: UUID
    ) -> (rate: Double, algorithmRate: Double, isCustom: Bool) {
        let day = date.onlyDate()
        let algorithm = algorithmRate(specialty: specialty, date: day, hospitalID: hospitalID)
        if let entry = entries.first(where: {
            $0.hospitalID == hospitalID &&
            Calendar.current.isDate($0.date, inSameDayAs: day) &&
            $0.specialty == specialty
        }) {
            return (entry.rate, algorithm, true)
        }
        return (algorithm, algorithm, false)
    }

    func setRate(_ rate: Double, specialty: String, date: Date, hospitalID: UUID) {
        let day = date.onlyDate()
        entries.removeAll {
            $0.hospitalID == hospitalID &&
            Calendar.current.isDate($0.date, inSameDayAs: day) &&
            $0.specialty == specialty
        }
        entries.append(Entry(hospitalID: hospitalID, date: day, specialty: specialty, rate: rate))
        save()
    }

    func resetToAlgorithm(specialty: String, date: Date, hospitalID: UUID) {
        let day = date.onlyDate()
        entries.removeAll {
            $0.hospitalID == hospitalID &&
            Calendar.current.isDate($0.date, inSameDayAs: day) &&
            $0.specialty == specialty
        }
        save()
    }

    // MARK: - Per-doctor day rates (long-press day → specialty → doctor)

    func doctorDayRate(
        doctorID: UUID,
        date: Date,
        hospitalID: UUID,
        fallback: Double
    ) -> Double {
        let day = date.onlyDate()
        if let entry = doctorDayEntries.first(where: {
            $0.hospitalID == hospitalID &&
            $0.doctorID == doctorID &&
            Calendar.current.isDate($0.date, inSameDayAs: day)
        }) {
            return entry.rate
        }
        return fallback
    }

    func setDoctorDayRate(_ rate: Double, doctorID: UUID, date: Date, hospitalID: UUID) {
        let day = date.onlyDate()
        doctorDayEntries.removeAll {
            $0.hospitalID == hospitalID &&
            $0.doctorID == doctorID &&
            Calendar.current.isDate($0.date, inSameDayAs: day)
        }
        doctorDayEntries.append(DoctorDayEntry(hospitalID: hospitalID, date: day, doctorID: doctorID, rate: rate))
        saveDoctorDays()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        }
        if let data = UserDefaults.standard.data(forKey: doctorDayKey),
           let decoded = try? JSONDecoder().decode([DoctorDayEntry].self, from: data) {
            doctorDayEntries = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func saveDoctorDays() {
        guard let data = try? JSONEncoder().encode(doctorDayEntries) else { return }
        UserDefaults.standard.set(data, forKey: doctorDayKey)
        objectWillChange.send()
    }
}

extension PricingObservables {
    static func from(market: MarketConditions) -> PricingObservables {
        PricingObservables(
            openShiftCount: market.openShiftCount,
            availableDoctorCount: market.availableDoctorCount,
            recentFillRate: market.recentFillRate,
            daysUntilShift: market.daysUntilShift,
            sampleSize: market.openShiftCount + (market.recentFillRate != nil ? 8 : 0)
        )
    }
}
