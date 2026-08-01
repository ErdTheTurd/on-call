import Foundation
import Combine

// MARK: - Unavailable Days Store

@MainActor
public final class UnavailableDaysStore: ObservableObject {
    public static let shared = UnavailableDaysStore()

    private let storageKey = "unavailable_days_v1"
    @Published private(set) var blockedByHospital: [UUID: Set<Date>] = [:]

    private init() { load() }

    public func isBlocked(_ date: Date, hospitalID: UUID) -> Bool {
        let day = date.onlyDate()
        return blockedByHospital[hospitalID]?.contains(day) ?? false
    }

    public func isBlockedOnAnyHospital(_ date: Date, hospitalIDs: [UUID]) -> Bool {
        hospitalIDs.contains { isBlocked(date, hospitalID: $0) }
    }

    public func toggle(_ date: Date, hospitalID: UUID) {
        let day = date.onlyDate()
        var set = blockedByHospital[hospitalID] ?? []
        if set.contains(day) { set.remove(day) } else { set.insert(day) }
        blockedByHospital[hospitalID] = set
        save()
    }

    public func blockedDates(for hospitalID: UUID) -> Set<Date> {
        blockedByHospital[hospitalID] ?? []
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([UUID: [Date]].self, from: data) else { return }
        blockedByHospital = stored.mapValues { Set($0) }
    }

    private func save() {
        let encoded = blockedByHospital.mapValues { Array($0) }
        if let data = try? JSONEncoder().encode(encoded) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
