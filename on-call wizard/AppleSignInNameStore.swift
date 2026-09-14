import Foundation

/// Apple only sends `fullName` and `email` on the **first** Sign in with Apple.
/// Persist given name, family name, and email so a later session (and onboarding)
/// can still use them. Empty later values never wipe a stored non-empty value.
enum AppleSignInNameStore {
    private static let currentAppleUserKey = "apple_siwa_current_user_id"

    struct Identity: Equatable {
        var givenName: String
        var familyName: String
        var email: String

        static let empty = Identity(givenName: "", familyName: "", email: "")

        var hasCompleteName: Bool {
            !trimmed(givenName).isEmpty && !trimmed(familyName).isEmpty
        }

        var hasEmail: Bool {
            !trimmed(email).isEmpty
        }
    }

    typealias PersonName = Identity

    /// Saves non-empty Apple name/email for this Apple user id.
    /// Empty incoming values never overwrite a name or email we already stored.
    static func persist(appleUserID: String, fullName: PersonNameComponents?, email: String? = nil) {
        let id = appleUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }

        let incomingGiven = trimmed(fullName?.givenName)
        let incomingFamily = trimmed(fullName?.familyName)
        let incomingEmail = trimmed(email)
        let existing = load(appleUserID: id)

        let given = incomingGiven.isEmpty ? existing.givenName : incomingGiven
        let family = incomingFamily.isEmpty ? existing.familyName : incomingFamily
        let mail = incomingEmail.isEmpty ? existing.email : incomingEmail

        if !given.isEmpty {
            UserDefaults.standard.set(given, forKey: givenKey(id))
        }
        if !family.isEmpty {
            UserDefaults.standard.set(family, forKey: familyKey(id))
        }
        if !mail.isEmpty {
            UserDefaults.standard.set(mail, forKey: emailKey(id))
        }
        UserDefaults.standard.set(id, forKey: currentAppleUserKey)
    }

    /// Tie the latest Apple user id to this app session so onboarding can look the
    /// identity up without applying a previous SIWA profile to an email/Google account
    /// on the same device.
    static func bindSession(userID: UUID) {
        guard let appleID = UserDefaults.standard.string(forKey: currentAppleUserKey), !appleID.isEmpty else { return }
        UserDefaults.standard.set(appleID, forKey: sessionKey(userID))
    }

    static func load(appleUserID: String) -> Identity {
        Identity(
            givenName: UserDefaults.standard.string(forKey: givenKey(appleUserID)) ?? "",
            familyName: UserDefaults.standard.string(forKey: familyKey(appleUserID)) ?? "",
            email: UserDefaults.standard.string(forKey: emailKey(appleUserID)) ?? ""
        )
    }

    static func identity(forSessionUserID userID: UUID?) -> Identity {
        guard let userID,
              let appleID = UserDefaults.standard.string(forKey: sessionKey(userID)),
              !appleID.isEmpty else {
            return .empty
        }
        return load(appleUserID: appleID)
    }

    static func name(forSessionUserID userID: UUID?) -> Identity {
        identity(forSessionUserID: userID)
    }

    private static func givenKey(_ appleUserID: String) -> String {
        "apple_siwa.given.\(appleUserID)"
    }

    private static func familyKey(_ appleUserID: String) -> String {
        "apple_siwa.family.\(appleUserID)"
    }

    private static func emailKey(_ appleUserID: String) -> String {
        "apple_siwa.email.\(appleUserID)"
    }

    private static func sessionKey(_ userID: UUID) -> String {
        "apple_siwa.session.\(userID.uuidString)"
    }

    private static func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
