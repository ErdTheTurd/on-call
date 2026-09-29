import Foundation
import Combine

// MARK: - SendGrid Email Service

final class SendGridService {
    static let shared = SendGridService()

    private var apiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "SENDGRID_API_KEY") as? String) ?? ""
    }
    private let opsNotifyEmail = "erdunn706@gmail.com"
    private let fromEmail = "noreply@mdshift.net"
    private let fromName  = Brand.appName
    #if DEBUG
    private let isDev = true
    #else
    private let isDev = false
    #endif

    enum SendError: LocalizedError {
        case networkError(Error)
        case serverError(Int, String)
        case invalidCode

        var errorDescription: String? {
            switch self {
            case .networkError(let e): return "Network error: \(e.localizedDescription)"
            case .serverError(let code, let msg): return "Server error \(code): \(msg)"
            case .invalidCode: return "Invalid or expired verification code."
            }
        }
    }

    // MARK: - Generate Code

    func generateCode() -> String {
        String(format: "%06d", Int.random(in: 0...999999))
    }

    // MARK: - Send Verification Code

    func sendVerificationCode(to email: String, code: String, recipientName: String) async throws {
        if SupabaseConfig.isConfigured {
            _ = try await SupabaseHTTPClient.shared.invokeFunction(
                name: "send-notification",
                body: [
                    "to": isDev ? opsNotifyEmail : email,
                    "subject": "Your \(Brand.appName) verification code",
                    "html": """
                    <div style="font-family:-apple-system,sans-serif;max-width:480px;margin:0 auto;padding:32px">
                      <h2>\(Brand.appName)</h2>
                      <p>Hi \(recipientName),</p>
                      <p>Your verification code is:</p>
                      <div style="background:#f0f4ff;border-radius:12px;padding:24px;text-align:center;margin:24px 0">
                        <span style="font-size:42px;font-weight:700;letter-spacing:12px;color:#2563eb">\(code)</span>
                      </div>
                      <p style="color:#888;font-size:14px">This code expires in 10 minutes.</p>
                    </div>
                    """
                ]
            )
            return
        }
        guard !apiKey.isEmpty else { return }
        let recipient = isDev ? opsNotifyEmail : email
        let devNote = isDev ? "<p style='color:#888;font-size:12px;'>DEV: actual recipient would be \(email)</p>" : ""

        let body: [String: Any] = [
            "personalizations": [[
                "to": [["email": recipient, "name": recipientName]],
                "subject": "Your \(Brand.appName) verification code"
            ]],
            "from": ["email": fromEmail, "name": fromName],
            "content": [[
                "type": "text/html",
                "value": """
                <div style="font-family:-apple-system,sans-serif;max-width:480px;margin:0 auto;padding:32px">
                  <h2 style="color:#1a1a2e;margin-bottom:8px">\(Brand.appName)</h2>
                  <p style="color:#555">Hi \(recipientName),</p>
                  <p style="color:#555">Your verification code is:</p>
                  <div style="background:#f0f4ff;border-radius:12px;padding:24px;text-align:center;margin:24px 0">
                    <span style="font-size:42px;font-weight:700;letter-spacing:12px;color:#2563eb">\(code)</span>
                  </div>
                  <p style="color:#888;font-size:14px">This code expires in 10 minutes. If you didn't request this, ignore this email.</p>
                  \(devNote)
                </div>
                """
            ]]
        ]

        guard let url = URL(string: "https://api.sendgrid.com/v3/mail/send"),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw SendError.serverError(http.statusCode, msg)
            }
        } catch let e as SendError {
            throw e
        } catch {
            throw SendError.networkError(error)
        }
    }

    // MARK: - Send Shift Notification

    func sendShiftAcceptedNotification(to email: String, doctorName: String, shift: Shift) async {
        let recipient = isDev ? opsNotifyEmail : email
        let body: [String: Any] = [
            "personalizations": [[
                "to": [["email": recipient]],
                "subject": "Shift Accepted — \(shift.hospital)"
            ]],
            "from": ["email": fromEmail, "name": fromName],
            "content": [[
                "type": "text/html",
                "value": """
                <div style="font-family:-apple-system,sans-serif;max-width:480px;margin:0 auto;padding:32px">
                  <h2 style="color:#1a1a2e">Shift Confirmed</h2>
                  <p>Dr. \(doctorName) has accepted a shift at <strong>\(shift.hospital)</strong>.</p>
                  <ul>
                    <li>Specialty: \(shift.specialty)</li>
                    <li>Start: \(shift.start.formatted(date: .complete, time: .shortened))</li>
                    <li>Duration: \(shift.durationHours)h</li>
                    <li>Rate: $\(Int(shift.currentRate))/hr</li>
                  </ul>
                </div>
                """
            ]]
        ]
        guard let url = URL(string: "https://api.sendgrid.com/v3/mail/send"),
              let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Hospital signup notifications

    /// Emails ops (you) + the hospital after a hospital finishes onboarding.
    func notifyHospitalSignup(
        hospitalName: String,
        hospitalEmail: String,
        npi: String,
        flags: [String]
    ) async {
        let safeName = hospitalName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeEmail = hospitalEmail.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let flagBlock = flags.isEmpty
            ? "<p>No automated review flags.</p>"
            : "<ul>" + flags.map { "<li>\($0)</li>" }.joined() + "</ul>"

        let opsHTML = """
        <div style="font-family:-apple-system,sans-serif;max-width:560px;margin:0 auto;padding:32px">
          <h2 style="color:#1a1a2e">New hospital signup</h2>
          <p>A hospital just finished onboarding on \(Brand.appName).</p>
          <ul>
            <li><strong>Hospital:</strong> \(safeName)</li>
            <li><strong>Work email:</strong> \(safeEmail)</li>
            <li><strong>NPI:</strong> \(npi)</li>
          </ul>
          <p><strong>Flags</strong></p>
          \(flagBlock)
          <p>Please reach out to them to continue onboarding.</p>
        </div>
        """

        let hospitalHTML = """
        <div style="font-family:-apple-system,sans-serif;max-width:560px;margin:0 auto;padding:32px">
          <h2 style="color:#1a1a2e">Thanks for joining \(Brand.appName)</h2>
          <p>Hi \(safeName) team,</p>
          <p>We received your hospital signup. Someone from our team will contact you at <strong>\(safeEmail)</strong> shortly to finish setup and answer questions.</p>
          <p>If you need anything sooner, reply to this email or write erdunn706@gmail.com.</p>
          <p style="color:#888;font-size:14px">— \(Brand.appName)</p>
        </div>
        """

        await sendRaw(
            to: opsNotifyEmail,
            subject: "New hospital signup — \(safeName)",
            html: opsHTML
        )
        await sendRaw(
            to: isDev ? opsNotifyEmail : safeEmail,
            subject: "We'll be in touch — \(Brand.appName)",
            html: hospitalHTML + (isDev ? "<p style='color:#888;font-size:12px'>DEV: hospital copy for \(safeEmail)</p>" : "")
        )
    }

    private func sendRaw(to email: String, subject: String, html: String) async {
        if SupabaseConfig.isConfigured {
            _ = try? await SupabaseHTTPClient.shared.invokeFunction(
                name: "send-notification",
                body: ["to": email, "subject": subject, "html": html]
            )
            return
        }
        guard !apiKey.isEmpty,
              let url = URL(string: "https://api.sendgrid.com/v3/mail/send"),
              let bodyData = try? JSONSerialization.data(withJSONObject: [
                "personalizations": [["to": [["email": email]], "subject": subject]],
                "from": ["email": fromEmail, "name": fromName],
                "content": [["type": "text/html", "value": html]]
              ] as [String: Any]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        _ = try? await URLSession.shared.data(for: request)
    }
}

// MARK: - Pending Code Store (in-memory, TTL 10 min)

@MainActor
final class EmailVerificationStore: ObservableObject {
    static let shared = EmailVerificationStore()
    private var codes: [String: (code: String, expiry: Date)] = [:]

    func issue(for email: String) -> String {
        let code = SendGridService.shared.generateCode()
        codes[email.lowercased()] = (code, Date().addingTimeInterval(600))
        return code
    }

    func validate(email: String, code: String) -> Bool {
        let key = email.lowercased()
        guard let entry = codes[key] else { return false }
        guard Date() < entry.expiry else { codes.removeValue(forKey: key); return false }
        guard entry.code == code else { return false }
        codes.removeValue(forKey: key)
        return true
    }
}
