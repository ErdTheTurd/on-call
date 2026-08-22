import Foundation

/**
 Keeps the local doctor id equal to the Supabase auth user id.

 Supabase keys doctors by `doctor_profiles.profile_id`, which is the auth user
 id. The app originally minted a random `DoctorProfile.id`, so every token
 request, assignment, and trade written from the device referenced an id the
 server had never seen — those writes failed their foreign key and the doctor
 stayed invisible to the hospital.

 On sign-in we adopt the auth id and rewrite the local records that still point
 at the old one, so a doctor who used the app before this change keeps their
 shifts.
 */
@MainActor
enum DoctorIdentity {

    /// Adopts the auth user id as the doctor id, migrating local records once.
    @discardableResult
    static func reconcile() -> UUID? {
        guard var profile = DoctorProfile.load() else { return nil }
        guard let authID = profile.userID ?? SessionStore.shared.currentUserID else { return nil }
        guard profile.id != authID else { return authID }

        let previous = profile.id
        profile.id = authID
        profile.userID = authID
        profile.save()

        remap(from: previous, to: authID)
        return authID
    }

    private static func remap(from previous: UUID, to next: UUID) {
        AssignedShiftsStore.shared.remapDoctor(from: previous, to: next)
        TokenStore.shared.remapDoctor(from: previous, to: next)
        DoctorRosterStore.shared.remapDoctor(from: previous, to: next)
        PenaltyLedgerStore.shared.remapDoctor(from: previous, to: next)
        ShiftTradeService.shared.remapDoctor(from: previous, to: next)
    }
}
