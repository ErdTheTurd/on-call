import Foundation
import Combine

// MARK: - Saved / named pricing algorithms

struct AlgorithmPreset: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    /// Built-in Smart Algo — always first, cannot be deleted.
    var isSmart: Bool
    var disabledVariables: [String]
    /// Manual multipliers keyed by factor id (0.1…2.0). Absent = use algo auto value.
    var factorOverrides: [String: Double]
    var caseVolumeRewardEnabled: Bool
    var caseVolumeRewardScale: Int
    var caseVolumeRewardAuto: Bool

    static let smartID = UUID(uuidString: "AAAAAAAA-0001-0000-0000-000000000001")!

    static func smartAlgo() -> AlgorithmPreset {
        AlgorithmPreset(
            id: smartID,
            name: "Smart Algo",
            isSmart: true,
            disabledVariables: [],
            factorOverrides: [:],
            caseVolumeRewardEnabled: true,
            caseVolumeRewardScale: 40,
            caseVolumeRewardAuto: true
        )
    }
}

@MainActor
final class AlgorithmPresetStore: ObservableObject {
    static let shared = AlgorithmPresetStore()

    private let storageKey = "algorithm_presets_v1"
    private let activeKey = "algorithm_active_v1"
    private let weekdayKey = "algorithm_weekday_v1"

    @Published var presets: [AlgorithmPreset] = []
    @Published var activePresetID: UUID = AlgorithmPreset.smartID
    /// Calendar weekday (1=Sun … 7=Sat) → preset id applied to that weekday.
    @Published var weekdayAssignments: [Int: UUID] = [:]

    /// Live edit buffer for the active preset (Smart Algo edits stay ephemeral until saved).
    @Published var workingOverrides: [String: Double] = [:]
    @Published var workingDisabled: [String] = []

    var activePreset: AlgorithmPreset {
        presets.first { $0.id == activePresetID } ?? .smartAlgo()
    }

    private init() {
        load()
        ensureSmartAlgo()
        syncWorkingFromActive()
    }

    func selectPreset(_ id: UUID) {
        guard presets.contains(where: { $0.id == id }) else { return }
        // Persist edits into current non-smart preset before switching
        commitWorkingIfNeeded()
        activePresetID = id
        UserDefaults.standard.set(id.uuidString, forKey: activeKey)
        syncWorkingFromActive()
    }

    func setOverride(_ id: String, value: Double) {
        let clamped = min(2.0, max(0.1, (value * 100).rounded() / 100))
        if abs(clamped - 1.0) < 0.001 {
            workingOverrides.removeValue(forKey: id)
            if !workingDisabled.contains(id) { workingDisabled.append(id) }
        } else {
            workingOverrides[id] = clamped
            workingDisabled.removeAll { $0 == id }
        }
        objectWillChange.send()
        commitWorkingIfNeeded()
    }

    /// Seed a working override without treating 1.0 as "off" (used when opening the slider).
    func seedWorkingOverride(_ id: String, value: Double) {
        let clamped = min(2.0, max(0.1, (value * 100).rounded() / 100))
        workingOverrides[id] = clamped
        workingDisabled.removeAll { $0 == id }
        objectWillChange.send()
        commitWorkingIfNeeded()
    }

    func clearOverride(_ id: String) {
        workingOverrides.removeValue(forKey: id)
        workingDisabled.removeAll { $0 == id }
        objectWillChange.send()
        commitWorkingIfNeeded()
    }

    func setEnabled(_ id: String, enabled: Bool) {
        if enabled {
            workingDisabled.removeAll { $0 == id }
            if workingOverrides[id].map({ abs($0 - 1.0) < 0.001 }) == true {
                workingOverrides.removeValue(forKey: id)
            }
        } else {
            if !workingDisabled.contains(id) { workingDisabled.append(id) }
            workingOverrides.removeValue(forKey: id)
        }
        objectWillChange.send()
        commitWorkingIfNeeded()
    }

    func isEnabled(_ id: String) -> Bool {
        !workingDisabled.contains(id)
    }

    /// Effective multiplier for display: override if present, else component's algo value.
    func effectiveMultiplier(id: String, algoValue: Double) -> Double {
        if workingDisabled.contains(id) { return 1.0 }
        return workingOverrides[id] ?? algoValue
    }

    @discardableResult
    func saveAsNew(name: String, fromPolicy policy: SchedulingPolicy) -> AlgorithmPreset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = AlgorithmPreset(
            id: UUID(),
            name: trimmed.isEmpty ? "Custom Algo" : trimmed,
            isSmart: false,
            disabledVariables: workingDisabled,
            factorOverrides: workingOverrides,
            caseVolumeRewardEnabled: policy.caseVolumeRewardEnabled,
            caseVolumeRewardScale: policy.caseVolumeRewardScale,
            caseVolumeRewardAuto: policy.caseVolumeRewardAuto
        )
        presets.append(preset)
        save()
        selectPreset(preset.id)
        return preset
    }

    func deletePreset(_ id: UUID) {
        guard id != AlgorithmPreset.smartID else { return }
        presets.removeAll { $0.id == id }
        weekdayAssignments = weekdayAssignments.filter { $0.value != id }
        if activePresetID == id { selectPreset(AlgorithmPreset.smartID) }
        save()
    }

    /// Assign the active algorithm to every occurrence of `weekday` (1=Sun…7=Sat).
    func assignWeekday(_ weekday: Int) {
        weekdayAssignments[weekday] = activePresetID
        saveWeekdays()
    }

    func clearWeekday(_ weekday: Int) {
        weekdayAssignments.removeValue(forKey: weekday)
        saveWeekdays()
    }

    func preset(forWeekday weekday: Int) -> AlgorithmPreset? {
        guard let id = weekdayAssignments[weekday] else { return nil }
        return presets.first { $0.id == id }
    }

    // MARK: - Persistence helpers

    private func commitWorkingIfNeeded() {
        guard let idx = presets.firstIndex(where: { $0.id == activePresetID }),
              !presets[idx].isSmart else { return }
        presets[idx].disabledVariables = workingDisabled
        presets[idx].factorOverrides = workingOverrides
        save()
    }

    private func syncWorkingFromActive() {
        let p = activePreset
        workingOverrides = p.isSmart ? [:] : p.factorOverrides
        workingDisabled = p.isSmart ? [] : p.disabledVariables
    }

    private func ensureSmartAlgo() {
        if !presets.contains(where: { $0.isSmart || $0.id == AlgorithmPreset.smartID }) {
            presets.insert(.smartAlgo(), at: 0)
        } else if let idx = presets.firstIndex(where: { $0.id == AlgorithmPreset.smartID }) {
            presets[idx].name = "Smart Algo"
            presets[idx].isSmart = true
            if idx != 0 {
                let smart = presets.remove(at: idx)
                presets.insert(smart, at: 0)
            }
        }
        save()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([AlgorithmPreset].self, from: data) {
            presets = decoded
        }
        if let raw = UserDefaults.standard.string(forKey: activeKey),
           let id = UUID(uuidString: raw) {
            activePresetID = id
        }
        if let data = UserDefaults.standard.data(forKey: weekdayKey),
           let decoded = try? JSONDecoder().decode([Int: UUID].self, from: data) {
            weekdayAssignments = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        UserDefaults.standard.set(activePresetID.uuidString, forKey: activeKey)
        saveWeekdays()
    }

    private func saveWeekdays() {
        if let data = try? JSONEncoder().encode(weekdayAssignments) {
            UserDefaults.standard.set(data, forKey: weekdayKey)
        }
    }
}
