import Foundation
import AuthenticationServices
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

enum AuthServiceError: LocalizedError {
    case emailNotConfirmed
    case needsEmailVerification
    case invalidResponse
    case passwordsDoNotMatch
    case invalidOTP
    case oauthCancelled
    case oauthFailed(String)

    var errorDescription: String? {
        switch self {
        case .emailNotConfirmed:
            return "Enter the 6-digit code from your email before signing in."
        case .needsEmailVerification:
            return "Check your email for a 6-digit code, then enter it here."
        case .invalidResponse:
            return "Unexpected response from the server."
        case .passwordsDoNotMatch:
            return "Passwords don't match."
        case .invalidOTP:
            return "Enter the 6-digit code from your email."
        case .oauthCancelled:
            return "Sign-in was cancelled."
        case .oauthFailed(let message):
            return message
        }
    }
}

@MainActor
final class SupabaseAuthService: NSObject {
    static let shared = SupabaseAuthService()

    var isConfigured: Bool { SupabaseConfig.isConfigured }

    private let sessionKey = "supabase_access_token"
    private let refreshKey = "supabase_refresh_token"
    private let userIDKey = "supabase_user_id"

    private var oauthSession: ASWebAuthenticationSession?
    private var oauthContinuation: CheckedContinuation<URL, Error>?

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
        let body: [String: Any] = [
            "email": email,
            "password": password,
            "data": ["role": role.rawValue.lowercased()],
            "gotrue_meta_security": [:]
        ]
        let data = try await SupabaseHTTPClient.shared.request(
            path: "auth/v1/signup",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body)
        )
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
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

    func verifySignupOTP(email: String, token: String, role: UserRole) async throws -> (UUID, UserRole) {
        let code = token.filter(\.isNumber)
        guard code.count == 6 else { throw AuthServiceError.invalidOTP }

        let body: [String: Any] = [
            "email": email,
            "token": code,
            "type": "signup"
        ]
        let data = try await SupabaseHTTPClient.shared.request(
            path: "auth/v1/verify",
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

        persistSession(access: access, refresh: json?["refresh_token"] as? String, userID: userID)
        let metaRole = (user["user_metadata"] as? [String: Any])?["role"] as? String
        let resolved = UserRole(rawValue: (metaRole ?? role.rawValue).capitalized) ?? role
        try? await upsertProfile(userID: userID, email: email, role: resolved)
        return (userID, resolved)
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
        let body: [String: Any] = [
            "email": email,
            "type": "signup"
        ]
        _ = try await SupabaseHTTPClient.shared.request(
            path: "auth/v1/resend",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body)
        )
    }

    /// Google / Apple via browser OAuth (PKCE). Apple native id_token path is separate.
    func signInWithOAuth(provider: String, role: UserRole) async throws -> (UUID, String, UserRole) {
        guard provider == "google" || provider == "apple" else {
            throw AuthServiceError.oauthFailed("Unsupported provider.")
        }
        guard let base = SupabaseConfig.url else { throw SupabaseError.notConfigured }

        let verifier = Self.randomPKCEString()
        let challenge = Self.pkceChallenge(for: verifier)
        let redirect = "oncallwizard://auth-callback"
        var comps = URLComponents(url: base.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: redirect),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authURL = comps.url else { throw AuthServiceError.invalidResponse }

        let callbackURL = try await startOAuthSession(url: authURL, callbackScheme: "oncallwizard")
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthServiceError.oauthFailed("Missing authorization code.")
        }

        let body: [String: Any] = [
            "auth_code": code,
            "code_verifier": verifier
        ]
        let data = try await SupabaseHTTPClient.shared.request(
            path: "auth/v1/token?grant_type=pkce",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body)
        )
        return try await finishOAuthSession(data: data, preferredRole: role)
    }

    func signInWithAppleIDToken(_ idToken: String, nonce: String?, role: UserRole) async throws -> (UUID, String, UserRole) {
        var body: [String: Any] = [
            "provider": "apple",
            "id_token": idToken
        ]
        if let nonce, !nonce.isEmpty {
            body["nonce"] = nonce
        }
        let data = try await SupabaseHTTPClient.shared.request(
            path: "auth/v1/token?grant_type=id_token",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body)
        )
        return try await finishOAuthSession(data: data, preferredRole: role)
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
        UserDefaults.standard.removeObject(forKey: refreshKey)
        UserDefaults.standard.removeObject(forKey: userIDKey)
    }

    // MARK: - Private

    private func finishOAuthSession(data: Data, preferredRole: UserRole) async throws -> (UUID, String, UserRole) {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let access = json?["access_token"] as? String,
              let user = json?["user"] as? [String: Any],
              let idStr = user["id"] as? String,
              let userID = UUID(uuidString: idStr) else {
            throw AuthServiceError.invalidResponse
        }
        persistSession(access: access, refresh: json?["refresh_token"] as? String, userID: userID)
        let email = (user["email"] as? String) ?? ""

        if let role = try await fetchRole(userID: userID) {
            return (userID, email, role)
        }
        let metaRole = (user["user_metadata"] as? [String: Any])?["role"] as? String
        let role = UserRole(rawValue: (metaRole ?? preferredRole.rawValue).capitalized) ?? preferredRole
        try? await upsertProfile(userID: userID, email: email, role: role)
        return (userID, email, role)
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

    private func startOAuthSession(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.oauthContinuation = continuation
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
                guard let self else { return }
                if let error {
                    let ns = error as NSError
                    if ns.domain == ASWebAuthenticationSessionErrorDomain,
                       ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        self.oauthContinuation?.resume(throwing: AuthServiceError.oauthCancelled)
                    } else {
                        self.oauthContinuation?.resume(throwing: AuthServiceError.oauthFailed(error.localizedDescription))
                    }
                    self.oauthContinuation = nil
                    return
                }
                guard let callbackURL else {
                    self.oauthContinuation?.resume(throwing: AuthServiceError.oauthFailed("No callback URL."))
                    self.oauthContinuation = nil
                    return
                }
                self.oauthContinuation?.resume(returning: callbackURL)
                self.oauthContinuation = nil
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.oauthSession = session
            if !session.start() {
                continuation.resume(throwing: AuthServiceError.oauthFailed("Could not start browser sign-in."))
                self.oauthContinuation = nil
            }
        }
    }

    private static func randomPKCEString(length: Int = 64) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var result = ""
        result.reserveCapacity(length)
        for _ in 0..<length {
            result.append(alphabet.randomElement()!)
        }
        return result
    }

    private static func pkceChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension SupabaseAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return window
        }
        return scenes.flatMap(\.windows).first ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
