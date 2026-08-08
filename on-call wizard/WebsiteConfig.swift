import Foundation

enum WebsiteConfig {
    static var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "WEBSITE_BASE_URL") as? String,
              !raw.isEmpty, !raw.hasPrefix("$("),
              let url = URL(string: raw) else { return nil }
        return url
    }

    static var dashboardURL: URL? {
        baseURL?.appendingPathComponent("dashboard.html")
    }

    static var authURL: URL? {
        baseURL?.appendingPathComponent("auth.html")
    }
}
