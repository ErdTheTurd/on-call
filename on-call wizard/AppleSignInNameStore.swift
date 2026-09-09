import Foundation

/// Apple only sends `PersonNameComponents` on the **first** Sign in with Apple.
/// Persist given/family name so a later session (and doctor onboarding) can still use it.
enum AppleSignInNameStore {
    private static let currentAppleUserKey = "apple_siwa_current_user_id"

    struct PersonName: Equatable {
        var givenName: String
        var familyName: String

        static let empty = PersonName(givenName: "", familyName: "")

        var hasCompleteName: Bool {
            !trimmed(givenName).isEmpty && !trimmed(familyName).isEmpty
        }
    }

    /// Saves a non-empty Apple name for this Apple user id. Empty values never overwrite a name we already stored.
    static func persist(appleUserID: String, fullName: PersonNameComponents?) {
        let id = appleUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }

        let incomingGiven = trimmed(fullName?.givenName)
        let incomingFamily = trimmed(fullName?.familyName)
        let existing = load(appleUserID: id)

        let given = incomingGiven.isEmpty ? existing.givenName : incomingGiven
        let family = incomingFamily.isEmpty ? existing.familyName : incomingFamily

        if !given.isEmpty {
            UserDefaults.standard.set(given, forKey: givenKey(id))
        }
        if !family.isEmpty {
            UserDefaults.standard.set(family, forKey: familyKey(id))
        }
        UserDefaults.standard.set(id, forKey: currentAppleUserKey)
    }

    /// Tie the latest Apple user id to this app session so onboarding can look the name up
    /// without applying a previous SIWA name to an email/Google account on the same device.
    static func bindSession(userID: UUID) {
        guard let appleID = UserDefaults.standard.string(forKey: currentAppleUserKey), !appleID.isEmpty else { return }
        UserDefaults.standard.set(appleID, forKey: sessionKey(userID))
    }

    static func load(appleUserID: String) -> PersonName {
        PersonName(
            givenName: UserDefaults.standard.string(forKey: givenKey(appleUserID)) ?? "",
            familyName: UserDefaults.standard.string(forKey: familyKey(appleUserID)) ?? ""
        )
    }

    static func name(forSessionUserID userID: UUID?) -> PersonName {
        guard let userID,
              let appleID = UserDefaults.standard.string(forKey: sessionKey(userID)),
              !appleID.isEmpty else {
            return .empty
        }
        return load(appleUserID: appleID)
    }

    private static func givenKey(_ appleUserID: String) -> String {
        "apple_siwa.given.\(appleUserID)"
    }

    private static func familyKey(_ appleUserID: String) -> String {
        "apple_siwa.family.\(appleUserID)"
    }

    private static func sessionKey(_ userID: UUID) -> String {
        "apple_siwa.session.\(userID.uuidString)"
    }

    private static func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
