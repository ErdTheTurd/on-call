import Foundation

enum AuthServiceError: LocalizedError {
    case emailNotConfirmed
    case needsEmailVerification
    case invalidResponse
    case passwordsDoNotMatch

    var errorDescription: String? {
        switch self {
        case .emailNotConfirmed:
            return "Confirm your email before signing in. Check your inbox for the link."
        case .needsEmailVerification:
            return "Check your email for a verification link, then sign in."
        case .invalidResponse:
            return "Unexpected response from the server."
        case .passwordsDoNotMatch:
            return "Passwords don't match."
        }
    }
}

@MainActor
final class SupabaseAuthService {
    static let shared = SupabaseAuthService()

    var isConfigured: Bool { SupabaseConfig.isConfigured }

    private let sessionKey = "supabase_access_token"
    private let refreshKey = "supabase_refresh_token"
    private let userIDKey = "supabase_user_id"

    var accessToken: String? { UserDefaults.standard.string(forKey: sessionKey) }
    var currentUserID: UUID? {
        guard let raw = UserDefaults.standard.string(forKey: userIDKey) else { return nil }
        return UUID(uuidString: raw)
    }

    struct SignUpResult {
        let userID: UUID
        let needsEmailVerification: Bool
    }

    func signUp(email: String, password: String, role: UserRole) async throws -> SignUpResult {
        let redirect = SupabaseConfig.websiteBaseURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/callback.html"
        let body: [String: Any] = [
            "email": email,
            "password": password,
            "data": ["role": role.rawValue.lowercased()],
            "gotrue_meta_security": [:],
            "email_redirect_to": redirect
        ]
        let data = try await SupabaseHTTPClient.shared.request(
            path: "auth/v1/signup",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body)
        )
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        // Newer GoTrue wraps the user at top-level; older responses nest under "user".
        let user = (json?["user"] as? [String: Any]) ?? json
        guard let idStr = user?["id"] as? String,
              let userID = UUID(uuidString: idStr) else {
            throw AuthServiceError.invalidResponse
        }

        let access = json?["access_token"] as? String
        let confirmed = (user?["email_confirmed_at"] as? String)?.isEmpty == false
            || (user?["confirmed_at"] as? String)?.isEmpty == false
        let needsVerification = access == nil || !confirmed

        if let access {
            persistSession(access: access, refresh: json?["refresh_token"] as? String, userID: userID)
            try await upsertProfile(userID: userID, email: email, role: role)
        }

        return SignUpResult(userID: userID, needsEmailVerification: needsVerification)
    }

    func signIn(email: String, password: String) async throws -> (UUID, UserRole) {
        let body: [String: Any] = ["email": email, "password": password]
        do {
            let data = try await SupabaseHTTPClient.shared.request(
                path: "auth/v1/token?grant_type=password",
                method: "POST",
                body: try JSONSerialization.data(withJSONObject: body)
            )
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let access = json?["access_token"] as? String,
                  let user = json?["user"] as? [String: Any],
                  let idStr = user["id"] as? String,
                  let userID = UUID(uuidString: idStr) else {
                throw AuthServiceError.invalidResponse
            }

            let confirmed = (user["email_confirmed_at"] as? String)?.isEmpty == false
                || (user["confirmed_at"] as? String)?.isEmpty == false
            if !confirmed {
                signOut()
                throw AuthServiceError.emailNotConfirmed
            }

            persistSession(access: access, refresh: json?["refresh_token"] as? String, userID: userID)
            if let role = try await fetchRole(userID: userID) {
                return (userID, role)
            }
            let metaRole = (user["user_metadata"] as? [String: Any])?["role"] as? String
            let role = UserRole(rawValue: (metaRole ?? "doctor").capitalized) ?? .doctor
            try? await upsertProfile(userID: userID, email: email, role: role)
            return (userID, role)
        } catch let http as SupabaseError {
            if case .server(let message) = http, message.localizedCaseInsensitiveContains("email not confirmed") {
                throw AuthServiceError.emailNotConfirmed
            }
            throw http
        }
    }

    func resendSignupEmail(email: String) async throws {
        let redirect = SupabaseConfig.websiteBaseURL
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/callback.html"
        let body: [String: Any] = [
            "email": email,
            "type": "signup",
            "email_redirect_to": redirect
        ]
        _ = try await SupabaseHTTPClient.shared.request(
            path: "auth/v1/resend",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body)
        )
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
        UserDefaults.standard.removeObject(forKey: refreshKey)
        UserDefaults.standard.removeObject(forKey: userIDKey)
    }

    private func persistSession(access: String, refresh: String?, userID: UUID) {
        UserDefaults.standard.set(access, forKey: sessionKey)
        if let refresh { UserDefaults.standard.set(refresh, forKey: refreshKey) }
        UserDefaults.standard.set(userID.uuidString, forKey: userIDKey)
    }

    private func upsertProfile(userID: UUID, email: String, role: UserRole) async throws {
        let row: [String: Any] = [
            "id": userID.uuidString,
            "email": email,
            "role": role.rawValue.lowercased()
        ]
        _ = try await SupabaseHTTPClient.shared.request(
            path: "rest/v1/profiles",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: row),
            accessToken: accessToken,
            prefer: "resolution=merge-duplicates"
        )
    }

    private func fetchRole(userID: UUID) async throws -> UserRole? {
        let data = try await SupabaseHTTPClient.shared.request(
            path: "rest/v1/profiles?id=eq.\(userID.uuidString)&select=role",
            accessToken: accessToken
        )
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let raw = rows.first?["role"] as? String else { return nil }
        return UserRole(rawValue: raw.capitalized)
    }
}
