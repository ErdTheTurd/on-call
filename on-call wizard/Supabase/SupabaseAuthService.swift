import Foundation

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

    func signUp(email: String, password: String, role: UserRole) async throws -> UUID {
        let body: [String: Any] = ["email": email, "password": password]
        let data = try await SupabaseHTTPClient.shared.request(
            path: "auth/v1/signup",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body)
        )
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let user = json?["user"] as? [String: Any],
              let idStr = user["id"] as? String,
              let userID = UUID(uuidString: idStr) else {
            throw SupabaseError.invalidResponse
        }
        if let access = json?["access_token"] as? String {
            persistSession(access: access, refresh: json?["refresh_token"] as? String, userID: userID)
        }
        try await upsertProfile(userID: userID, email: email, role: role)
        return userID
    }

    func signIn(email: String, password: String) async throws -> (UUID, UserRole) {
        let body: [String: Any] = ["email": email, "password": password]
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
            throw SupabaseError.invalidResponse
        }
        persistSession(access: access, refresh: json?["refresh_token"] as? String, userID: userID)
        let role = try await fetchRole(userID: userID) ?? .doctor
        return (userID, role)
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
            accessToken: accessToken
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
