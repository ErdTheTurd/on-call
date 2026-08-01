import Foundation

/// Stripe Connect integration stub — wire to backend when merchant account is ready.
@MainActor
final class PaymentService {
    static let shared = PaymentService()

    var isStripeConfigured: Bool {
        Bundle.main.object(forInfoDictionaryKey: "STRIPE_PUBLISHABLE_KEY") != nil
    }

    func recordPenaltyCharge(doctorID: UUID, amount: Decimal, shiftID: UUID) async throws {
        // Local ledger already tracks penalties; Stripe charge via edge function when configured.
        guard SupabaseConfig.isConfigured else { return }
        _ = try await SupabaseHTTPClient.shared.invokeFunction(
            name: "charge-penalty",
            body: [
                "doctor_id": doctorID.uuidString,
                "shift_id": shiftID.uuidString,
                "amount": NSDecimalNumber(decimal: amount).doubleValue
            ],
            accessToken: SupabaseAuthService.shared.accessToken
        )
    }

    func fetchPayoutHistory(doctorID: UUID) async -> [PayoutRecord] {
        guard SupabaseConfig.isConfigured else { return [] }
        return []
    }

    struct PayoutRecord: Identifiable {
        let id: UUID
        let amount: Decimal
        let paidAt: Date
    }
}
