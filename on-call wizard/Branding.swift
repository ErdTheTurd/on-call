import SwiftUI

// MARK: - Brand Tokens

enum Brand {
    // Background & surfaces
    static let bg           = Color(hex: "070B17")
    static let surface      = Color.white.opacity(0.05)   // keep transparent so it composites over any bg
    static let surfaceHigh  = Color.white.opacity(0.09)
    static let border       = Color.white.opacity(0.08)
    static let borderHigh   = Color.white.opacity(0.14)

    // Accent palette
    static let accent       = Color(hex: "4F8EF7")
    static let accentAlt    = Color(hex: "8B5CF6")
    static let accentSoft   = Color(hex: "4F8EF7").opacity(0.14)

    // Text
    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.52)
    static let textTertiary  = Color.white.opacity(0.28)

    // Semantic
    static let danger  = Color(hex: "F87171")
    static let success = Color(hex: "34D399")
    static let warning = Color(hex: "FBBF24")

    // Gradients
    static let accentGradient = LinearGradient(
        colors: [Color(hex: "4F8EF7"), Color(hex: "7C3AED")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // Geometry
    static let cardRadius:    CGFloat = 18
    static let buttonRadius:  CGFloat = 14
    static let cardPadding:   CGFloat = 20
    static let sectionSpacing: CGFloat = 12
    static let brandFont = Font.system(.body, design: .default)
}

// MARK: - Card Modifier

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Brand.cardPadding)
            .background {
                RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.white.opacity(0.075), Color.white.opacity(0.03)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                    .strokeBorder(LinearGradient(
                        colors: [Color.white.opacity(0.16), Color.white.opacity(0.04)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ), lineWidth: 1)
            }
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
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - Background

struct BackgroundGradient: View {
    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                ZStack {
                    Ellipse()
                        .fill(Color(hex: "1E3A8A").opacity(0.38))
                        .frame(width: 420, height: 300)
                        .blur(radius: 85)
                        .offset(x: -w * 0.1, y: h * 0.02)
                    Ellipse()
                        .fill(Color(hex: "5B21B6").opacity(0.28))
                        .frame(width: 340, height: 240)
                        .blur(radius: 80)
                        .offset(x: w * 0.55, y: h * 0.1)
                    Ellipse()
                        .fill(Color(hex: "1E40AF").opacity(0.2))
                        .frame(width: 460, height: 320)
                        .blur(radius: 100)
                        .offset(x: w * 0.05, y: h * 0.62)
                }
            }
            .ignoresSafeArea()
        }
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

// MARK: - Value Chip (used next to slider labels)

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
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 1)
    }
}

// Color(hex:) is defined in AuthView.swift
