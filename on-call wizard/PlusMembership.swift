import Foundation
import Combine

/// MD Shift+ ($9.99/mo) — synced from `profiles.plus_*` via Supabase.
@MainActor
final class PlusMembershipStore: ObservableObject {
    static let shared = PlusMembershipStore()

    static let priceLabel = "$9.99/mo"
    static let tokenBonus = 2

    /// Flip when ready to charge (~1 year after launch). Until then: no Plus CTAs, ad-free.
    static let isMonetizationLive = false

    @Published private(set) var isActive = false
    @Published private(set) var until: Date?
    @Published var lastError: String?

    private let defaultsKey = "md_shift_plus_v1"

    private init() {
        loadLocal()
        if !Self.isMonetizationLive { isActive = true }
    }

    var showsAds: Bool { Self.isMonetizationLive && !isActive }

    func refresh() async {
        guard Self.isMonetizationLive else {
            isActive = true
            lastError = nil
            return
        }
        guard SupabaseConfig.isConfigured,
              let token = SupabaseAuthService.shared.accessToken,
              let userId = SupabaseAuthService.shared.currentUserID else {
            loadLocal()
            return
        }
        do {
            let data = try await SupabaseHTTPClient.shared.request(
                path: "rest/v1/profiles?id=eq.\(userId.uuidString)&select=plus_active,plus_until",
                accessToken: token
            )
            struct Row: Decodable {
                let plus_active: Bool?
                let plus_until: String?
            }
            let rows = try JSONDecoder().decode([Row].self, from: data)
            let row = rows.first
            let remoteActive = row?.plus_active == true
            let end = Self.parseISO8601(row?.plus_until)
            if let end, end < Date() {
                apply(active: false, until: end)
            } else {
                apply(active: remoteActive, until: end)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            loadLocal()
        }
    }

    /// Opens web Stripe checkout (same account unlocks iOS). Avoids App Store IAP for v1.
    func startCheckout() async -> URL? {
        lastError = nil

        if let url = paymentLinkURL() {
            return url
        }

        guard SupabaseConfig.isConfigured,
              let token = SupabaseAuthService.shared.accessToken else {
            lastError = "Sign in to subscribe."
            return WebsiteConfig.plusCheckoutFallbackURL
        }

        do {
            let data = try await SupabaseHTTPClient.shared.invokeFunction(
                name: "create-plus-checkout",
                body: [:],
                accessToken: token
            )
            struct Resp: Decodable { let url: String?; let error: String? }
            let resp = try JSONDecoder().decode(Resp.self, from: data)
            if let err = resp.error, !err.isEmpty {
                lastError = err
                return nil
            }
            guard let raw = resp.url, let url = URL(string: raw) else {
                lastError = "Checkout URL missing."
                return WebsiteConfig.plusCheckoutFallbackURL
            }
            return url
        } catch {
            lastError = error.localizedDescription
            return WebsiteConfig.plusCheckoutFallbackURL
        }
    }

    // MARK: - Private

    private func paymentLinkURL() -> URL? {
        guard let link = Bundle.main.object(forInfoDictionaryKey: "STRIPE_PLUS_PAYMENT_LINK") as? String,
              !link.isEmpty, !link.hasPrefix("$("),
              var comps = URLComponents(string: link) else { return nil }
        if let userId = SupabaseAuthService.shared.currentUserID {
            var items = comps.queryItems ?? []
            items.append(URLQueryItem(name: "client_reference_id", value: userId.uuidString))
            comps.queryItems = items
        }
        return comps.url
    }

    private func apply(active: Bool, until: Date?) {
        isActive = Self.isMonetizationLive ? active : true
        self.until = until
        let payload: [String: Any] = [
            "active": active,
            "until": until.map { ISO8601DateFormatter().string(from: $0) } as Any
        ]
        UserDefaults.standard.set(payload, forKey: defaultsKey)
        NotificationCenter.default.post(name: .mdShiftPlusDidChange, object: nil)
    }

    private func loadLocal() {
        if !Self.isMonetizationLive {
            isActive = true
            return
        }
        guard let dict = UserDefaults.standard.dictionary(forKey: defaultsKey) else {
            isActive = false
            until = nil
            return
        }
        isActive = dict["active"] as? Bool ?? false
        until = Self.parseISO8601(dict["until"] as? String)
    }

    private static func parseISO8601(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

extension Notification.Name {
    static let mdShiftPlusDidChange = Notification.Name("mdShiftPlusDidChange")
}
