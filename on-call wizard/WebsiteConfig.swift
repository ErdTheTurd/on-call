import Foundation

enum WebsiteConfig {
    static var baseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "WEBSITE_BASE_URL") as? String,
              !raw.isEmpty, !raw.hasPrefix("$("),
              let url = URL(string: raw) else { return nil }
        return url
    }

    static var supportURL: URL {
        baseURL?.appendingPathComponent("support/")
            ?? URL(string: "https://mdshift.net/support/")!
    }

    static var plusCheckoutFallbackURL: URL? {
        let root = baseURL ?? URL(string: "https://mdshift.net")!
        var comps = URLComponents(url: root, resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "open", value: "plus")]
        return comps?.url ?? URL(string: "https://mdshift.net/?open=plus")
    }

    static var dashboardURL: URL? {
        baseURL?.appendingPathComponent("dashboard.html")
    }

    static var authURL: URL? {
        baseURL?.appendingPathComponent("auth.html")
    }
}
