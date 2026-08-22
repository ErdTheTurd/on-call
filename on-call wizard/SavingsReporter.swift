import Foundation
import Combine

/**
 Hospital savings telemetry — the iOS half of `docs/assets/js/domain/savings.js`.

 Every dollar we claim a hospital saved becomes one auditable row in
 `hospital_savings_events`, so the hospital card and the MD Shift admin
 dashboard read the same number instead of each re-deriving it.
 */
@MainActor
public final class SavingsReporter: ObservableObject {
    public static let shared = SavingsReporter()

    public enum Kind: String, Codable {
        case penaltyCancel = "penalty_cancel"
        case penaltyTrade = "penalty_trade"
        case rateSavings = "rate_savings"
    }

    /// Worst case the escalator reaches — mirrors `EscalationCurve` endpoints.
    private enum Ceiling {
        static let perDay = 2.0
        static let perHour = 2.2
    }

    public struct Event: Codable, Identifiable {
        public var id: String { eventKey }
        public let eventKey: String
        public let hospitalID: UUID
        public let hospitalName: String?
        public let shiftID: UUID?
        public let specialty: String?
        public let kind: Kind
        public let amount: Double
        public let occurredAt: Date
    }

    @Published public private(set) var events: [Event] = []
    private let storageKey = "hospital_savings_events_v1"

    private init() { load() }

    // MARK: - Recording

    /// Escalation the hospital never pays because this shift filled early.
    public static func rateSavings(for shift: Shift) -> Double {
        if case .flat = shift.escalationMode { return 0 }
        let floor = shift.rateFloor
        guard floor > 0 else { return 0 }

        let perDay = shift.rateUnit == .perDay
        let ceiling = floor * (perDay ? Ceiling.perDay : Ceiling.perHour)
        let avoidedPerUnit = max(0, ceiling - shift.currentRate)
        let units = perDay ? 1.0 : Double(shift.durationHours)
        return (avoidedPerUnit * units).rounded()
    }

    public func recordFill(shift: Shift, doctorID: UUID) {
        let amount = Self.rateSavings(for: shift)
        guard amount > 0 else { return }
        record(
            hospitalID: shift.hospitalID,
            hospitalName: shift.hospital,
            shiftID: shift.id,
            specialty: shift.specialty,
            kind: .rateSavings,
            amount: amount,
            actorID: doctorID
        )
    }

    public func recordPenalty(
        hospitalID: UUID,
        shiftID: UUID,
        doctorID: UUID,
        type: PenaltyLedgerStore.EntryType,
        amount: Decimal,
        specialty: String? = nil,
        hospitalName: String? = nil
    ) {
        let value = NSDecimalNumber(decimal: amount).doubleValue
        guard value > 0 else { return }
        record(
            hospitalID: hospitalID,
            hospitalName: hospitalName,
            shiftID: shiftID,
            specialty: specialty,
            kind: type == .trade ? .penaltyTrade : .penaltyCancel,
            amount: value,
            actorID: doctorID
        )
    }

    private func record(
        hospitalID: UUID,
        hospitalName: String?,
        shiftID: UUID?,
        specialty: String?,
        kind: Kind,
        amount: Double,
        actorID: UUID
    ) {
        // Deterministic key so a retry or a second device can't double count.
        let key = "\(kind.rawValue):\(shiftID?.uuidString ?? "none"):\(actorID.uuidString)"
        guard !events.contains(where: { $0.eventKey == key }) else { return }

        let event = Event(
            eventKey: key,
            hospitalID: hospitalID,
            hospitalName: hospitalName,
            shiftID: shiftID,
            specialty: specialty,
            kind: kind,
            amount: amount,
            occurredAt: Date()
        )
        events.append(event)
        save()

        Task { await push(event) }
    }

    // MARK: - Supabase

    private func push(_ event: Event) async {
        guard SupabaseConfig.isConfigured,
              let token = SupabaseAuthService.shared.accessToken,
              let userID = SupabaseAuthService.shared.currentUserID else { return }

        var row: [String: Any] = [
            "event_key": event.eventKey,
            "hospital_id": event.hospitalID.uuidString,
            "kind": event.kind.rawValue,
            "amount": event.amount,
            "occurred_at": ISO8601DateFormatter().string(from: event.occurredAt),
            "source": "ios",
            "created_by": userID.uuidString
        ]
        if let name = event.hospitalName { row["hospital_name"] = name }
        if let shiftID = event.shiftID { row["shift_id"] = shiftID.uuidString }
        if let specialty = event.specialty { row["specialty"] = specialty }

        guard let body = try? JSONSerialization.data(withJSONObject: [row]) else { return }
        _ = try? await SupabaseHTTPClient.shared.request(
            path: "rest/v1/hospital_savings_events?on_conflict=event_key",
            method: "POST",
            body: body,
            accessToken: token,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    /// Pulls this hospital's rows (including ones doctors wrote) into the local cache.
    public func refresh(hospitalID: UUID) async {
        guard SupabaseConfig.isConfigured,
              let token = SupabaseAuthService.shared.accessToken else { return }

        struct Row: Decodable {
            let event_key: String
            let hospital_id: UUID
            let hospital_name: String?
            let shift_id: UUID?
            let specialty: String?
            let kind: String
            let amount: Double
            let occurred_at: String
        }

        guard let data = try? await SupabaseHTTPClient.shared.request(
            path: "rest/v1/hospital_savings_events?hospital_id=eq.\(hospitalID.uuidString)&select=*&order=occurred_at.desc&limit=2000",
            accessToken: token
        ), let rows = try? JSONDecoder().decode([Row].self, from: data) else { return }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var merged: [String: Event] = Dictionary(uniqueKeysWithValues: events.map { ($0.eventKey, $0) })

        for row in rows {
            guard let kind = Kind(rawValue: row.kind) else { continue }
            merged[row.event_key] = Event(
                eventKey: row.event_key,
                hospitalID: row.hospital_id,
                hospitalName: row.hospital_name,
                shiftID: row.shift_id,
                specialty: row.specialty,
                kind: kind,
                amount: row.amount,
                occurredAt: iso.date(from: row.occurred_at)
                    ?? ISO8601DateFormatter().date(from: row.occurred_at)
                    ?? Date()
            )
        }

        events = merged.values.sorted { $0.occurredAt < $1.occurredAt }
        save()
    }

    // MARK: - Summary

    public struct Summary {
        public var total: Double = 0
        public var penalties: Double = 0
        public var rateSavings: Double = 0
        public var count: Int = 0
        public var trackedSince: Date?
        public var bySpecialty: [(String, Double)] = []

        public var perDay: Double {
            guard let since = trackedSince else { return total }
            let days = max(1, Date().timeIntervalSince(since) / 86_400)
            return total / days
        }
    }

    public func summary(for hospitalID: UUID) -> Summary {
        var out = Summary()
        var specialties: [String: Double] = [:]

        for event in events where event.hospitalID == hospitalID {
            out.total += event.amount
            out.count += 1
            if event.kind == .rateSavings { out.rateSavings += event.amount }
            else { out.penalties += event.amount }
            specialties[event.specialty ?? "General", default: 0] += event.amount
            if out.trackedSince == nil || event.occurredAt < out.trackedSince! {
                out.trackedSince = event.occurredAt
            }
        }

        out.bySpecialty = specialties.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
        return out
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([Event].self, from: data) else { return }
        events = stored
    }

    private func save() {
        if let data = try? JSONEncoder().encode(events.suffix(500).map { $0 }) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
