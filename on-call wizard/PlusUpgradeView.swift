import SwiftUI

/// MD Shift+ upgrade sheet — doctors and hospitals.
struct PlusUpgradeView: View {
    var role: Role = .doctor
    @ObservedObject private var plus = PlusMembershipStore.shared
    @State private var busy = false
    @State private var message: String?
    @Environment(\.openURL) private var openURL

    enum Role { case doctor, hospital }

    private var features: [(title: String, detail: String)] {
        var shared: [(String, String)] = [
            ("Ad-free workspace", "Sponsored slots disappear across Dashboard and Doctors."),
            ("Priority badge", "Requests and posts carry a calm Plus mark."),
            ("Faster support lane", "Same inbox — tagged Plus so we triage you first."),
        ]
        if role == .doctor {
            shared += [
                ("+2 daily tokens", "Request more call days without waiting for reset."),
                ("Earnings clarity", "Projected vs completed stays one tap away."),
            ]
        } else {
            shared += [
                ("Coverage control room", "Analytics and alter tools with Plus shortcuts."),
                ("Priority posting", "Open shifts surface higher when doctors browse."),
            ]
        }
        return shared
    }

    var body: some View {
        ZStack {
            BackgroundGradient()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(Brand.plusName, systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                        Text(plus.isActive ? "You're on \(Brand.plusName)" : "Upgrade to \(Brand.plusName)")
                            .font(.title2.bold())
                        Text(plus.isActive
                             ? "Ad-free and perks are active on this account (web + iOS)."
                             : "Unlock an ad-free workspace at \(PlusMembershipStore.priceLabel).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if plus.isActive {
                            Label("Plus active", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                        } else {
                            Button {
                                Task { await checkout() }
                            } label: {
                                Text(busy ? "Opening checkout…" : "Get \(Brand.plusName) · \(PlusMembershipStore.priceLabel)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(busy)
                            Text("Subscribe on the web via Stripe — same login unlocks Plus here. Cancel anytime.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(16)
                    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Included").font(.headline)
                        ForEach(features, id: \.title) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.subheadline.weight(.semibold))
                                Text(item.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(16)
                    .background(Brand.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if let message {
                        Text(message).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(Brand.plusName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await plus.refresh() }
    }

    private func checkout() async {
        busy = true
        defer { busy = false }
        if let url = await plus.startCheckout() {
            openURL(url)
            message = nil
        } else {
            message = plus.lastError ?? "Could not start checkout."
        }
    }
}
