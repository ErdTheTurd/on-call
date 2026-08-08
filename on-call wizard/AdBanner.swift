import SwiftUI

// MARK: - Ad Banner
// Placeholder ad slots for investor demos. Gate with InvestorDemo.isEnabled.
// Replace content with a real SDK (AdMob / AppLovin) when shipping.

struct AdBannerView: View {
    var placement: String = "dashboard"

    private static let slots: [(title: String, subtitle: String, cta: String, tint: String)] = [
        ("LocumTenens.com", "Fill critical gaps this weekend", "Learn more", "2563EB"),
        ("MedMal Shield", "Malpractice coverage from $89/mo", "Get a quote", "059669"),
        ("DocuSign Health", "Credential packets in minutes", "Try free", "7C3AED"),
        ("ShiftPay Capital", "Advance earnings same day", "Apply now", "D97706"),
    ]

    @State private var index = 0

    var body: some View {
        if InvestorDemo.isEnabled {
            content
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 12_000_000_000)
                        index = (index + 1) % Self.slots.count
                    }
                }
        }
    }

    private var slot: (title: String, subtitle: String, cta: String, tint: String) {
        Self.slots[index % Self.slots.count]
    }

    private var content: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: slot.tint).opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: slot.tint))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Ad")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Brand.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Brand.border.opacity(0.5), in: Capsule())
                    Text(slot.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Brand.textPrimary)
                        .lineLimit(1)
                }
                Text(slot.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Text(slot.cta)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(hex: slot.tint), in: Capsule())
        }
        .padding(12)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Brand.border, lineWidth: 1)
        }
        .accessibilityLabel("Advertisement: \(slot.title)")
    }
}
