import SwiftUI
import UIKit

// MARK: - Theme Manager

final class ThemeManager {
    static let shared = ThemeManager()
    static let storageKey = "app_theme_v1"

    enum Theme: String, CaseIterable, Identifiable {
        case light  = "Light"
        case dark   = "Dark"
        case system = "System"

        var id: String { rawValue }

        var colorScheme: ColorScheme? {
            switch self {
            case .light:  return .light
            case .dark:   return .dark
            case .system: return nil
            }
        }

        static func from(storage raw: String) -> Theme {
            Theme(rawValue: raw) ?? .system
        }

        /// Maps to UIKit window override. `.unspecified` follows the phone
        /// (including Light/Dark scheduled by time of day).
        var interfaceStyle: UIUserInterfaceStyle {
            switch self {
            case .light:  return .light
            case .dark:   return .dark
            case .system: return .unspecified
            }
        }
    }

    private init() {}

    @MainActor
    static func applyWindowStyle(_ theme: Theme) {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = theme.interfaceStyle
            }
        }
    }
}

// MARK: - App-wide color scheme (Light / Dark / System)

struct AppColorSchemeModifier: ViewModifier {
    @AppStorage(ThemeManager.storageKey) private var themeRaw: String = ThemeManager.Theme.system.rawValue

    private var theme: ThemeManager.Theme { ThemeManager.Theme.from(storage: themeRaw) }

    @ViewBuilder
    func body(content: Content) -> some View {
        Group {
            switch theme {
            case .light:
                content.preferredColorScheme(.light)
            case .dark:
                content.preferredColorScheme(.dark)
            case .system:
                // No SwiftUI override — follow phone appearance (incl. time-of-day schedule).
                content
            }
        }
        .onAppear { ThemeManager.applyWindowStyle(theme) }
        .onChange(of: themeRaw) { _, _ in
            ThemeManager.applyWindowStyle(theme)
        }
    }
}

extension View {
    /// Applies the user's Appearance preference (Light / Dark / System).
    /// System matches the rest of the phone, including scheduled Light/Dark.
    func appColorScheme() -> some View {
        modifier(AppColorSchemeModifier())
    }
}

// MARK: - Brand Tokens

enum Brand {
    /// Public product name under the icon / App Store listing.
    static let appName = "MD Shift Demo"
    static let plusName = "MD Shift+"

    // ── Backgrounds ──────────────────────────────────────────────────────────
    static let bg = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(hex: "070B17")
            : UIColor(hex: "F8FBFF")
    })

    static let surface = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.05)
            : UIColor(hex: "FFFFFF")
    })

    static let surfaceHigh = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.09)
            : UIColor(hex: "EFF6FF")
    })

    static let border = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.08)
            : UIColor(hex: "BFDBFE")
    })

    static let borderHigh = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.14)
            : UIColor(hex: "93C5FD")
    })

    // ── Accent palette ───────────────────────────────────────────────────────
    static let accent    = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(hex: "4F8EF7")
            : UIColor(hex: "2563EB")
    })

    static let accentAlt  = Color(hex: "7C3AED")
    static let accentSoft = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(hex: "4F8EF7").withAlphaComponent(0.14)
            : UIColor(hex: "2563EB").withAlphaComponent(0.10)
    })

    // ── Text ─────────────────────────────────────────────────────────────────
    static let textPrimary = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor.white
            : UIColor(hex: "0F172A")
    })

    static let textSecondary = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.52)
            : UIColor(hex: "475569")
    })

    static let textTertiary = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.28)
            : UIColor(hex: "94A3B8")
    })

    // ── Semantic ─────────────────────────────────────────────────────────────
    static let danger  = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(hex: "F87171") : UIColor(hex: "DC2626")
    })
    static let success = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(hex: "34D399") : UIColor(hex: "059669")
    })
    static let warning = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(hex: "FBBF24") : UIColor(hex: "D97706")
    })

    // ── Gradients ────────────────────────────────────────────────────────────
    static let accentGradient = LinearGradient(
        colors: [Color(hex: "2563EB"), Color(hex: "7C3AED")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // ── Geometry ─────────────────────────────────────────────────────────────
    static let cardRadius:     CGFloat = 18
    static let buttonRadius:   CGFloat = 14
    static let cardPadding:    CGFloat = 20
    static let sectionSpacing: CGFloat = 12
    static let brandFont = Font.system(.body, design: .default)
}

// MARK: - Adaptive helpers for UIColor

extension UIColor {
    convenience init(hex: String) {
        let h = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >>  8) & 0xFF) / 255
        let b = CGFloat( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Card Modifier

struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(Brand.cardPadding)
            .background {
                RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                    .fill(scheme == .dark
                          ? Color.white.opacity(0.07)
                          : Color.white.opacity(0.92))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                    .strokeBorder(
                        scheme == .dark ? Color.white.opacity(0.12) : Color(hex: "BFDBFE").opacity(0.7),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: scheme == .dark ? .clear : Color.black.opacity(0.04),
                radius: 6, x: 0, y: 2
            )
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}

// MARK: - Primary Button

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                RoundedRectangle(cornerRadius: Brand.buttonRadius, style: .continuous)
                    .fill(Brand.accentGradient)
                    .opacity(configuration.isPressed ? 0.8 : 1)
            }
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Background (lightweight — no live blur orbs)

struct BackgroundGradient: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if scheme == .dark {
                LinearGradient(
                    colors: [Color(hex: "070B17"), Color(hex: "0F172A"), Color(hex: "111827")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [Color(hex: "F8FBFF"), Color(hex: "EFF6FF"), Color(hex: "F5F3FF")],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 9) {
            if let img = systemImage {
                Image(systemName: img)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.accent)
                    .frame(width: 24, height: 24)
                    .background(Brand.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Brand.textPrimary)
        }
    }
}

// MARK: - Value Chip

struct ValueChip: View {
    let text: String
    var accent: Color = Brand.accent

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(accent.opacity(0.13), in: Capsule())
    }
}

// MARK: - Thin Divider

struct SubtleDivider: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Rectangle()
            .fill(scheme == .dark ? Color.white.opacity(0.06) : Color(hex: "E2E8F0"))
            .frame(height: 1)
    }
}

// MARK: - Theme Picker (reusable in settings)

struct ThemePickerRow: View {
    @AppStorage(ThemeManager.storageKey) private var themeRaw: String = ThemeManager.Theme.system.rawValue

    private var theme: Binding<ThemeManager.Theme> {
        Binding(
            get: { ThemeManager.Theme.from(storage: themeRaw) },
            set: { newValue in
                themeRaw = newValue.rawValue
                ThemeManager.applyWindowStyle(newValue)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Appearance", systemImage: "circle.lefthalf.filled")
                Spacer()
                Picker("", selection: theme) {
                    ForEach(ThemeManager.Theme.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }
            if theme.wrappedValue == .system {
                Text("Matches your phone — including Light/Dark by time of day.")
                    .font(.caption)
                    .foregroundStyle(Brand.textTertiary)
            }
        }
    }
}

// MARK: - Month Nav Button (theme-aware)

struct MonthNavButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.accent)
                .frame(width: 36, height: 36)
                .background(Brand.accentSoft, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Contact Support

struct ContactSupportFooter: View {
    private let supportURL = WebsiteConfig.supportURL

    var body: some View {
        Button {
            UIApplication.shared.open(supportURL)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "envelope")
                    .font(.system(size: 11, weight: .semibold))
                Text("Contact support")
                    .font(.system(size: 11, weight: .medium))
                Text("·")
                    .foregroundStyle(Brand.textTertiary)
                Text("mdshift.net/support")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.accent)
            }
            .foregroundStyle(Brand.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Contact support at mdshift.net/support")
    }
}

/// List row for hamburger dashboards (hospital / doctor).
struct ContactSupportRow: View {
    private let supportURL = WebsiteConfig.supportURL

    var body: some View {
        Button {
            UIApplication.shared.open(supportURL)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .foregroundStyle(Brand.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Contact support")
                        .foregroundStyle(Brand.textPrimary)
                    Text("mdshift.net/support")
                        .font(.caption)
                        .foregroundStyle(Brand.accent)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.textTertiary)
            }
        }
        .accessibilityLabel("Contact support at mdshift.net/support")
    }
}

extension View {
    /// Pins support above the bottom safe area (auth / onboarding only).
    func withContactSupport() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            ContactSupportFooter()
                .background(Brand.bg.opacity(0.94))
        }
    }
}

// MARK: - Professional success feedback (restrained delight)

struct ActionSuccessBanner: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Brand.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Brand.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Brand.success.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Brand.success.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateCard: View {
    let title: String
    let message: String
    var systemImage: String = "tray"
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Brand.accent)
                .frame(width: 52, height: 52)
                .background(Brand.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(title)
                .font(.headline)
                .foregroundStyle(Brand.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let onAction {
                Button(action: onAction) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}

// Color(hex:) is defined in AuthView.swift

// MARK: - Number formatting (thousand separators)

enum NumberFormat {
    private static let groupedInteger: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f
    }()

    private static func groupedDecimal(fractionDigits: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = fractionDigits
        f.minimumFractionDigits = fractionDigits
        return f
    }

    /// Groups thousands with commas (e.g. 1234 → "1,234").
    static func grouped(_ value: Int) -> String {
        groupedInteger.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Groups thousands with commas. Pass `fractionDigits` for decimals (e.g. 1234.5 → "1,234.5").
    static func grouped(_ value: Double, fractionDigits: Int = 0) -> String {
        if fractionDigits <= 0 {
            return grouped(Int(value.rounded()))
        }
        return groupedDecimal(fractionDigits: fractionDigits).string(from: NSNumber(value: value))
            ?? String(format: "%.\(fractionDigits)f", value)
    }

    static func currency(_ value: Int) -> String { "$" + grouped(value) }

    static func currency(_ value: Double, fractionDigits: Int = 0) -> String {
        "$" + grouped(value, fractionDigits: fractionDigits)
    }
}
