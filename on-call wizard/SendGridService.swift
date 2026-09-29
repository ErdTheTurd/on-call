import Foundation

// Thin client for the purpose-specific send-notification function.
// The server generates codes, builds HTML, and chooses recipients.

final class SendGridService {
    static let shared = SendGridService()

    enum SendError: LocalizedError {
        case invalidCode
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidCode: return "Incorrect or expired code."
            case .server(let msg): return msg
            }
        }
    }

    func requestVerificationCode(to email: String, recipientName: String) async throws {
        guard SupabaseConfig.isConfigured else {
            throw SendError.server("Email sending is not configured.")
        }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard address.contains("@") else { throw SendError.server("Enter a valid email first.") }
        _ = try await SupabaseHTTPClient.shared.invokeFunction(
            name: "send-notification",
            body: [
                "action": "send_code",
                "email": address,
                "recipientName": recipientName
            ],
            accessToken: SupabaseAuthService.shared.accessToken
        )
    }

    func verifyCode(email: String, code: String) async throws {
        guard SupabaseConfig.isConfigured else {
            throw SendError.server("Email sending is not configured.")
        }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let digits = String(code.filter { $0.isNumber }.prefix(6))
        guard digits.count == 6 else { throw SendError.invalidCode }
        let data = try await SupabaseHTTPClient.shared.invokeFunction(
            name: "send-notification",
            body: [
                "action": "verify_code",
                "email": address,
                "code": digits
            ],
            accessToken: SupabaseAuthService.shared.accessToken
        )
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let ok = json?["ok"] as? Bool == true
        let returned = (json?["email"] as? String)?.lowercased()
        guard ok, returned == address else { throw SendError.invalidCode }
    }

    /// Emails ops and the hospital after a hospital finishes onboarding.
    /// The server builds both messages and only mails this verified address plus OPS_EMAIL.
    func notifyHospitalSignup(
        hospitalName: String,
        hospitalEmail: String,
        npi: String,
        flags: [String]
    ) async throws {
        guard SupabaseConfig.isConfigured else { return }
        guard let token = SupabaseAuthService.shared.accessToken, !token.isEmpty else {
            throw SendError.server("Sign in before finishing hospital signup.")
        }
        let address = hospitalEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        _ = try await SupabaseHTTPClient.shared.invokeFunction(
            name: "send-notification",
            body: [
                "action": "hospital_signup",
                "name": hospitalName,
                "email": address,
                "npi": npi,
                "flags": flags
            ],
            accessToken: token
        )
    }
}
