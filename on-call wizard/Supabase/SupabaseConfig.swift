import Foundation

enum SupabaseConfig {
    static var url: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !raw.isEmpty, !raw.hasPrefix("$("),
              let url = URL(string: raw) else { return nil }
        return url
    }

    static var anonKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return key
    }

    static var isConfigured: Bool { url != nil && anonKey != nil }

    static var websiteBaseURL: String {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "WEBSITE_BASE_URL") as? String,
           !raw.isEmpty, !raw.hasPrefix("$(") {
            return raw
        }
        return "https://mdshift.net"
    }

    static var functionsURL: URL? {
        url?.appendingPathComponent("functions/v1")
    }
}

enum SupabaseError: LocalizedError {
    case notConfigured
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Supabase is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY."
        case .invalidResponse: return "Unexpected response from server."
        case .server(let msg): return msg
        }
    }
}

struct SupabaseHTTPClient {
    static let shared = SupabaseHTTPClient()

    func request(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        accessToken: String? = nil,
        prefer: String? = nil
    ) async throws -> Data {
        guard let base = SupabaseConfig.url, let key = SupabaseConfig.anonKey else {
            throw SupabaseError.notConfigured
        }
        // Paths may already include query strings — append carefully
        let url: URL
        if path.contains("?") {
            url = URL(string: base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + path)
                ?? base.appendingPathComponent(path)
        } else {
            url = base.appendingPathComponent(path)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseError.server(Self.humanizeError(data: data, status: http.statusCode))
        }
        return data
    }

    /// Prefer a short user-facing message over raw GoTrue / PostgREST JSON blobs.
    private static func humanizeError(data: Data, status: Int) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? "HTTP \(status)"
        }
        let raw = (json["error_description"] as? String)
            ?? (json["msg"] as? String)
            ?? (json["message"] as? String)
            ?? (json["error"] as? String)
            ?? "HTTP \(status)"
        let lower = raw.lowercased()
        if lower.contains("audience") || lower.contains("unacceptable") {
            return "Apple Sign In is not configured for this app. Please try email sign-in."
        }
        if lower.contains("nonce") {
            return "Apple Sign In could not be verified. Please try again."
        }
        if lower.contains("id token") || lower.contains("id_token") || lower.contains("provider is not enabled") {
            return "Sign in with Apple is temporarily unavailable. Try email sign-in, or try again later."
        }
        return raw
    }

    func invokeFunction(name: String, body: [String: Any], accessToken: String? = nil) async throws -> Data {
        guard let base = SupabaseConfig.functionsURL else { throw SupabaseError.notConfigured }
        var req = URLRequest(url: base.appendingPathComponent(name))
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue(SupabaseConfig.anonKey ?? "", forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let token = accessToken ?? SupabaseConfig.anonKey ?? ""
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseError.server(Self.humanizeError(data: data, status: http.statusCode))
        }
        return data
    }
}

/// Pages PostgREST lists in chunks the server will actually return.
/// Live `max_rows` is 1000, and a request for more is silently truncated.
/// A failed page throws so callers keep the previous local copy.
enum PostgRESTPages {
    static let pageSize = 1000
    private static let maxPages = 40

    /// UTC start of the current month, minus 7 days. Older rows stay on the server.
    static func windowStartISO(now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = calendar.dateComponents([.year, .month], from: now)
        let monthStart = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: parts.year,
            month: parts.month,
            day: 1
        )) ?? now
        let start = calendar.date(byAdding: .day, value: -7, to: monthStart) ?? monthStart
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: start)
    }

    static func fetchDataPages(basePath: String, accessToken: String?) async throws -> [Data] {
        var pages: [Data] = []
        for page in 0..<maxPages {
            let offset = page * pageSize
            let separator = basePath.contains("?") ? "&" : "?"
            let path = "\(basePath)\(separator)limit=\(pageSize)&offset=\(offset)"
            let data = try await SupabaseHTTPClient.shared.request(path: path, accessToken: accessToken)
            let count = try rowCount(data)
            pages.append(data)
            if count < pageSize { return pages }
        }
        throw SupabaseError.server("The server returned more rows than this sync can load. Nothing was replaced.")
    }

    static func fetchObjects(basePath: String, accessToken: String?) async throws -> [[String: Any]] {
        var all: [[String: Any]] = []
        let pages = try await fetchDataPages(basePath: basePath, accessToken: accessToken)
        for data in pages {
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw SupabaseError.invalidResponse
            }
            all.append(contentsOf: rows)
        }
        return all
    }

    private static func rowCount(_ data: Data) throws -> Int {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw SupabaseError.invalidResponse
        }
        return rows.count
    }
}
