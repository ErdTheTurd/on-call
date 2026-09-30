import Foundation

/// Device copies of profiles, shifts, roster, trades, and approvals.
/// Sign-in drops another person's copy before the new account is loaded.
/// Sign-out drops the copy so the next person on the device starts clean.
@MainActor
enum LocalAccountData {
    private static let ownerKey = "local_data_owner_id"

    static func prepareForSignIn(userID: UUID) {
        let current = UserDefaults.standard.string(forKey: ownerKey)
        if current != userID.uuidString {
            clearStoredData()
        }
        UserDefaults.standard.set(userID.uuidString, forKey: ownerKey)
    }

    static func clearOnSignOut() {
        clearStoredData()
        UserDefaults.standard.removeObject(forKey: ownerKey)
    }

    private static func clearStoredData() {
        let defaults = UserDefaults.standard
        let keys = [
            DoctorProfile.storageKey,
            HospitalProfile.storageKey,
            "doctor_roster_v1",
            "shift_trade_service_v2",
            "shift_trade_service_v1",
            "assigned_shifts_v1",
            "penalty_ledger_v1",
            "hospital_scheduling_policy_v1",
            "unavailable_days_v1",
            "investor_demo_seeded_v2",
            "hospital_shifts_v1",
            "doctor_tokens_v2",
            "algorithm_presets_v1",
            "algorithm_weekday_v1",
            "proposed_rates_v1",
            "doctor_day_rates_v1",
            "hospital_savings_events_v1",
            "saved_role",
            "accounts_v1",
            "md_shift_plus_v1",
            "session_current_user_id",
            "session_current_email",
            "doctor_prefs_v1",
            "doctor_min_rate",
            "doctor_days_ahead"
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("profile_push_fp_") {
            defaults.removeObject(forKey: key)
        }

        DoctorRosterStore.shared.clearAll()
        ShiftTradeService.shared.clearAll()
        AssignedShiftsStore.shared.clearAll()
        PenaltyLedgerStore.shared.clearAll()
        SchedulingPolicyStore.shared.clearAll()
        UnavailableDaysStore.shared.clearAll()
        TokenStore.shared.clearAll()
        Services.hospital.clearAll()
        SavingsReporter.shared.clearAll()
        ProposedRateStore.shared.clearAll()
        AlgorithmPresetStore.shared.clearAll()
        PlusMembershipStore.shared.clearLocal()
        DoctorPreferencesStore.shared.clearAll()
        Services.doctor.clearAvailability()
        InvestorDemo.resetSeedFlag()
    }
}
