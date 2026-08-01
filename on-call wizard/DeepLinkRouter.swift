import Foundation
import SwiftUI

enum DeepLinkRoute: Equatable {
    case home
    case auth
    case dashboard
    case shift(UUID)
}

@MainActor
final class DeepLinkRouter: ObservableObject {
    static let shared = DeepLinkRouter()

    @Published var pendingRoute: DeepLinkRoute?

    func handle(_ url: URL) {
        pendingRoute = parse(url)
    }

    func consumePendingRoute() -> DeepLinkRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }

    private func parse(_ url: URL) -> DeepLinkRoute? {
        if url.scheme?.lowercased() == "oncallwizard" {
            let segments = [url.host, url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            return parseSegments(segments)
        }

        if let website = WebsiteConfig.baseURL,
           url.host == website.host {
            let prefix = website.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            var trimmed = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !prefix.isEmpty, trimmed.hasPrefix(prefix) {
                trimmed = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            return parseSegments(trimmed.split(separator: "/").map(String.init))
        }

        return nil
    }

    private func parseSegments(_ segments: [String]) -> DeepLinkRoute? {
        guard let first = segments.first else { return .home }
        switch first {
        case "home": return .home
        case "auth", "auth.html": return .auth
        case "dashboard", "dashboard.html": return .dashboard
        case "shift":
            if segments.count > 1, let id = UUID(uuidString: segments[1]) { return .shift(id) }
            return nil
        default:
            return nil
        }
    }

    private func parsePath(_ rawPath: String) -> DeepLinkRoute? {
        let segments = rawPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .split(separator: "/")
            .map(String.init)
        return parseSegments(segments)
    }
}

struct DeepLinkBanner: View {
    let route: DeepLinkRoute
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("OK", action: onDismiss)
                .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
    }

    private var title: String {
        switch route {
        case .home: return "Opened from website"
        case .auth: return "Sign-in link received"
        case .dashboard: return "Dashboard link received"
        case .shift: return "Shift link received"
        }
    }

    private var subtitle: String {
        switch route {
        case .shift(let id): return "Shift \(id.uuidString.prefix(8))…"
        default: return "Connected to the On Call website"
        }
    }

    private var icon: String {
        switch route {
        case .shift: return "calendar.badge.clock"
        default: return "link"
        }
    }
}
