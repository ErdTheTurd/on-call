import Foundation
import Combine

// MARK: - Investor Demo Mode
// Flip `isEnabled` to `false` when wiring live data / shipping to production.
// All mock calendar fills, ads placeholders, and demo seeding gate on this flag.

enum InvestorDemo {
    /// Master switch — set to `false` to disable all investor mock data.
    static let isEnabled = true

    private static let seededKey = "investor_demo_seeded_v2"

    @MainActor
    static func bootstrapIfNeeded(hospitalID: UUID, hospitalName: String) {
        renameBayviewIfNeeded()
        guard isEnabled else { return }

        DoctorRosterStore.shared.seedMockDoctorsIfNeeded()
        seedPayRatesIfNeeded()

        // Always ensure shifts exist, then fill calendar coverage for the demo.
        let name = HospitalProfile.load()?.name ?? hospitalName
        Services.hospital.ensureDailyShifts(
            from: Date(),
            days: 90,
            hospitalID: hospitalID,
            hospitalName: name.isEmpty ? "Average Hospital" : name
        )
        renameShiftsHospital(hospitalID: hospitalID, to: "Average Hospital")

        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        seedCalendarAssignments(hospitalID: hospitalID)
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    /// Call this to re-seed mock fills after clearing data.
    @MainActor
    static func resetSeedFlag() {
        UserDefaults.standard.set(false, forKey: seededKey)
    }

    // MARK: - Rename

    @MainActor
    static func renameBayviewIfNeeded() {
        guard var profile = HospitalProfile.load() else { return }
        let lower = profile.name.lowercased()
        if lower.contains("bayview") {
            profile.name = "Average Hospital"
            if profile.email.lowercased().contains("bayview") {
                profile.email = "admin@averagehospital.org"
            }
            profile.save()
        }
    }

    @MainActor
    private static func renameShiftsHospital(hospitalID: UUID, to name: String) {
        let service = Services.hospital
        for shift in service.shifts where shift.hospitalID == hospitalID {
            guard shift.hospital != name else { continue }
            let updated = Shift(
                id: shift.id,
                hospitalID: shift.hospitalID,
                hospital: name,
                specialty: shift.specialty,
                start: shift.start,
                durationHours: shift.durationHours,
                rateFloor: shift.rateFloor,
                rateUnit: shift.rateUnit,
                escalationMode: shift.escalationMode,
                escalationIntervalHours: shift.escalationIntervalHours,
                usesAlgorithmPricing: shift.usesAlgorithmPricing
            )
            service.upsertShift(updated)
        }
    }

    // MARK: - Pay rates

    @MainActor
    private static func seedPayRatesIfNeeded() {
        var policy = SchedulingPolicyStore.shared.policy
        let defaults: [String: Double] = [
            "Internal Medicine": 1100,
            "Emergency Medicine": 1400,
            "Cardiology": 1600,
            "Surgery": 1800,
            "General Surgery": 1800,
            "Orthopedics": 1500,
            "Anesthesiology": 1450,
            "Radiology": 1300,
            "Pediatrics": 1050,
            "Neurology": 1550,
            "Psychiatry": 1000,
            "Ob/Gyn": 1350,
            "ENT": 1250,
            "Hospitalist": 1150,
        ]
        var changed = false
        for (sp, rate) in defaults where policy.specialtyBaseRates[sp] == nil {
            policy.specialtyBaseRates[sp] = rate
            changed = true
        }
        if changed {
            if let hid = HospitalProfile.load()?.id {
                SchedulingPolicyStore.shared.setPolicy(policy, for: hid)
            } else {
                SchedulingPolicyStore.shared.policy = policy
            }
        }
    }

    // MARK: - Calendar fill pattern
    // day % 3 == 0 → all specialties filled (green)
    // day % 3 == 1 → ~half filled (yellow)
    // day % 3 == 2 → none filled (red)

    @MainActor
    private static func seedCalendarAssignments(hospitalID: UUID) {
        let cal = Calendar.current
        let roster = DoctorRosterStore.shared.doctors
        guard !roster.isEmpty else { return }

        let shifts = Services.hospital.shifts.filter {
            $0.hospitalID == hospitalID && !$0.isPast
        }

        var byDay: [Date: [Shift]] = [:]
        for s in shifts {
            byDay[s.date.onlyDate(), default: []].append(s)
        }

        for (day, dayShifts) in byDay {
            let dayNum = cal.component(.day, from: day)
            let pattern = dayNum % 3
            let fillCount: Int
            switch pattern {
            case 0: fillCount = dayShifts.count          // all filled
            case 1: fillCount = max(1, dayShifts.count / 2) // partial
            default: fillCount = 0                       // none
            }
            let toFill = Array(dayShifts.prefix(fillCount))
            for shift in toFill {
                let candidates = roster.filter { $0.specialty == shift.specialty }
                guard let doctor = candidates.randomElement() else { continue }
                AssignedShiftsStore.shared.seedAssignmentIfNeeded(shift: shift, doctorID: doctor.id)
            }
        }
    }
}
