import Foundation
import SwiftUI
import Combine

// MARK: - Service Protocols

protocol DoctorService {
    func availabilitySettings() async throws -> (minRate: Double, daysAhead: Int)
    func setAvailability(minRate: Double, daysAhead: Int) async throws
    func recommendedShifts() async throws -> [Shift]
    func openShifts(for profile: DoctorProfile?) async throws -> [Shift]
    func accept(shift: Shift) async throws
}

protocol HospitalService {
    func openShifts() async throws -> [Shift]
    func postShift(_ shift: Shift) async throws
    func candidates(for shift: Shift) async throws -> [DoctorSummary]
}

// MARK: - In-Memory Implementations (persisted locally until Supabase sync)

@MainActor
final class InMemoryDoctorService: DoctorService, ObservableObject {
    private let minRateKey = "doctor_min_rate"
    private let daysAheadKey = "doctor_days_ahead"

    @Published var minRate: Double = 120
    @Published var daysAhead: Int = 7
    @Published var acceptedShifts: [Shift] = []

    init() {
        if UserDefaults.standard.object(forKey: minRateKey) != nil {
            minRate = UserDefaults.standard.double(forKey: minRateKey)
        }
        daysAhead = UserDefaults.standard.integer(forKey: daysAheadKey)
        if daysAhead == 0 { daysAhead = 7 }
    }

    func availabilitySettings() async throws -> (minRate: Double, daysAhead: Int) {
        (minRate, daysAhead)
    }

    func setAvailability(minRate: Double, daysAhead: Int) async throws {
        self.minRate = minRate
        self.daysAhead = daysAhead
        UserDefaults.standard.set(minRate, forKey: minRateKey)
        UserDefaults.standard.set(daysAhead, forKey: daysAheadKey)
    }

    func recommendedShifts() async throws -> [Shift] {
        try await openShifts(for: DoctorProfile.load())
    }

    func openShifts(for profile: DoctorProfile?) async throws -> [Shift] {
        let all = try await Services.hospital.openShifts()
        let specialties = Set(profile?.specialties ?? [])
        return all.filter { shift in
            guard !shift.isPast else { return false }
            guard !AssignedShiftsStore.shared.isShiftFilled(shift.id) else { return false }
            guard shift.currentRate >= minRate else { return false }
            if specialties.isEmpty { return false }
            return specialties.contains(shift.specialty)
        }
    }

    func accept(shift: Shift) async throws {
        guard !acceptedShifts.contains(where: { $0.id == shift.id }) else { return }
        acceptedShifts.append(shift)
    }
}

@MainActor
final class InMemoryHospitalService: HospitalService, ObservableObject {
    static let shared = InMemoryHospitalService()
    private let storageKey = "hospital_shifts_v1"

    @Published var shifts: [Shift]

    init(shifts: [Shift] = []) {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([Shift].self, from: data), !stored.isEmpty {
            self.shifts = stored
        } else {
            self.shifts = shifts
        }
    }

    func openShifts() async throws -> [Shift] { shifts.filter { !$0.isPast } }

    func postShift(_ shift: Shift) async throws {
        upsertShift(shift)
    }

    func candidates(for shift: Shift) async throws -> [DoctorSummary] {
        DoctorRosterStore.shared.doctors.filter { $0.specialty == shift.specialty }
    }

    func shift(
        on date: Date,
        specialty: String,
        hospitalID: UUID,
        hospitalName: String,
        policy: SchedulingPolicy? = nil,
        persistImmediately: Bool = true
    ) -> Shift {
        let policy = policy ?? SchedulingPolicy()
        let day = date.onlyDate()
        if let existing = shifts.first(where: {
            $0.hospitalID == hospitalID &&
            $0.specialty == specialty &&
            Calendar.current.isDate($0.date, inSameDayAs: day)
        }) {
            return existing
        }

        let unit: RateUnit = policy.granularity == .hour ? .perHour : .perDay
        // Prefer specialty base rate for seeding — full algo on every day is too slow.
        let base = policy.specialtyBaseRates[specialty]
            ?? (policy.granularity == .day ? 1_200 : 120)
        let newShift = Shift(
            hospitalID: hospitalID,
            hospital: hospitalName.isEmpty ? "Hospital" : hospitalName,
            specialty: specialty,
            start: day,
            durationHours: policy.granularity == .hour ? 12 : 24,
            rateFloor: base,
            rateUnit: unit,
            usesAlgorithmPricing: true
        )
        shifts.append(newShift)
        if persistImmediately { persist() }
        return newShift
    }

    /// Legacy helper — returns Internal Medicine shift for the day.
    func shift(on date: Date, hospitalID: UUID, hospitalName: String, policy: SchedulingPolicy? = nil) -> Shift {
        shift(on: date, specialty: "Internal Medicine", hospitalID: hospitalID, hospitalName: hospitalName, policy: policy)
    }

    func upsertShift(_ shift: Shift) {
        let day = shift.date.onlyDate()
        if let idx = shifts.firstIndex(where: {
            $0.hospitalID == shift.hospitalID &&
            $0.specialty == shift.specialty &&
            Calendar.current.isDate($0.date, inSameDayAs: day)
        }) {
            shifts[idx] = shift
        } else if let idx = shifts.firstIndex(where: { $0.id == shift.id }) {
            shifts[idx] = shift
        } else {
            shifts.append(shift)
        }
        persist()
    }

    func ensureDailyShifts(
        from start: Date,
        days count: Int,
        hospitalID: UUID,
        hospitalName: String,
        policy: SchedulingPolicy? = nil,
        specialties: [String]? = nil
    ) {
        let policy = policy ?? SchedulingPolicy()
        let cal = Calendar.current
        let specs = specialties?.isEmpty == false ? specialties! : DemoData.specialties
        let before = shifts.count
        for offset in 0..<count {
            guard let date = cal.date(byAdding: .day, value: offset, to: start.onlyDate()) else { continue }
            for specialty in specs {
                _ = shift(
                    on: date,
                    specialty: specialty,
                    hospitalID: hospitalID,
                    hospitalName: hospitalName,
                    policy: policy,
                    persistImmediately: false
                )
            }
        }
        if shifts.count != before { persist() }
    }

    /// Ensures every day in a calendar month has the given specialty shifts.
    func ensureMonthShifts(
        for month: Date,
        hospitalID: UUID,
        hospitalName: String,
        policy: SchedulingPolicy? = nil,
        specialties: [String]? = nil
    ) {
        let policy = policy ?? SchedulingPolicy()
        let cal = Calendar.current
        let monthStart = month.startOfMonth()
        guard let range = cal.range(of: .day, in: .month, for: monthStart) else { return }
        let specs = specialties?.isEmpty == false ? specialties! : DemoData.specialties
        let before = shifts.count
        for offset in range {
            guard let date = cal.date(byAdding: .day, value: offset - 1, to: monthStart) else { continue }
            for specialty in specs {
                _ = shift(
                    on: date,
                    specialty: specialty,
                    hospitalID: hospitalID,
                    hospitalName: hospitalName,
                    policy: policy,
                    persistImmediately: false
                )
            }
        }
        if shifts.count != before { persist() }
    }

    var openShiftCount: Int {
        shifts.filter { !$0.isPast && !AssignedShiftsStore.shared.isShiftFilled($0.id) }.count
    }

    var fillRatePercent: Int {
        let future = shifts.filter { !$0.isPast }
        guard !future.isEmpty else { return 0 }
        let filled = future.filter { AssignedShiftsStore.shared.isShiftFilled($0.id) }.count
        return Int((Double(filled) / Double(future.count)) * 100)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(shifts) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Service Locator

enum Services {
    static let doctor = InMemoryDoctorService()
    static let hospital = InMemoryHospitalService.shared
}
