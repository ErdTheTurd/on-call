import Foundation
import Combine
import SwiftUI

// MARK: - Points Events

public enum PointsEvent {
    case shiftAccepted
    case shiftCompleted
    case fastResponse   // accepted within 2 hours of posting
    case streakBonus(days: Int)

    public var points: Int {
        switch self {
        case .shiftAccepted:         return 50
        case .shiftCompleted:        return 200
        case .fastResponse:          return 75
        case .streakBonus(let days):
            switch days {
            case 3..<7:   return 100
            case 7..<14:  return 250
            case 14..<30: return 600
            default:      return 1500
            }
        }
    }

    public var label: String {
        switch self {
        case .shiftAccepted:         return "Shift Accepted"
        case .shiftCompleted:        return "Shift Completed"
        case .fastResponse:          return "Lightning Response"
        case .streakBonus(let d):    return "\(d)-Day Streak!"
        }
    }

    public var icon: String {
        switch self {
        case .shiftAccepted:  return "checkmark.circle.fill"
        case .shiftCompleted: return "star.fill"
        case .fastResponse:   return "bolt.fill"
        case .streakBonus:    return "flame.fill"
        }
    }
}

// MARK: - Doctor Level

public struct DoctorLevel {
    public let name: String
    public let minPoints: Int
    public let icon: String
    public let color: String  // hex

    public static let levels: [DoctorLevel] = [
        DoctorLevel(name: "Resident Level",     minPoints: 0,     icon: "stethoscope",          color: "#8E9AAF"),
        DoctorLevel(name: "Attending Level",    minPoints: 500,   icon: "cross.case.fill",       color: "#4A90D9"),
        DoctorLevel(name: "Fellow Level",       minPoints: 1500,  icon: "medal.fill",            color: "#7B68EE"),
        DoctorLevel(name: "Hospitalist Level",  minPoints: 3000,  icon: "building.2.fill",       color: "#2ECC71"),
        DoctorLevel(name: "Chief Level",        minPoints: 6000,  icon: "crown.fill",            color: "#F39C12"),
        DoctorLevel(name: "Department Head Level", minPoints: 12000, icon: "star.circle.fill",   color: "#E74C3C"),
    ]

    public static func level(for points: Int) -> DoctorLevel {
        levels.reversed().first { points >= $0.minPoints } ?? levels[0]
    }

    public static func nextLevel(for points: Int) -> DoctorLevel? {
        levels.first { $0.minPoints > points }
    }

    public static func progress(for points: Int) -> Double {
        let current = level(for: points)
        guard let next = nextLevel(for: points) else { return 1.0 }
        let range = Double(next.minPoints - current.minPoints)
        let earned = Double(points - current.minPoints)
        return min(1.0, earned / range)
    }
}

// MARK: - Points Store

@MainActor
public final class PointsStore: ObservableObject {
    public static let shared = PointsStore()

    private let storageKey = "doctor_points_v1"

    @Published public var totalPoints: Int = 0
    @Published public var currentStreak: Int = 0
    @Published public var lastShiftDate: Date? = nil
    @Published public var recentEvents: [(event: PointsEvent, date: Date)] = []

    private struct Stored: Codable {
        var totalPoints: Int
        var currentStreak: Int
        var lastShiftDate: Date?
    }

    public init() { load() }

    public func award(_ event: PointsEvent) {
        totalPoints += event.points
        recentEvents.insert((event, Date()), at: 0)
        if recentEvents.count > 20 { recentEvents.removeLast() }

        // Streak tracking
        if case .shiftCompleted = event {
            let cal = Calendar.current
            if let last = lastShiftDate, cal.isDateInYesterday(last) {
                currentStreak += 1
                if currentStreak >= 3 {
                    let bonus = PointsEvent.streakBonus(days: currentStreak)
                    totalPoints += bonus.points
                    recentEvents.insert((bonus, Date()), at: 0)
                }
            } else if lastShiftDate == nil || !cal.isDateInToday(lastShiftDate!) {
                currentStreak = 1
            }
            lastShiftDate = Date()
        }
        save()
    }

    public var level: DoctorLevel { DoctorLevel.level(for: totalPoints) }
    public var nextLevel: DoctorLevel? { DoctorLevel.nextLevel(for: totalPoints) }
    public var levelProgress: Double { DoctorLevel.progress(for: totalPoints) }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        totalPoints = stored.totalPoints
        currentStreak = stored.currentStreak
        lastShiftDate = stored.lastShiftDate
    }

    private func save() {
        let stored = Stored(totalPoints: totalPoints, currentStreak: currentStreak, lastShiftDate: lastShiftDate)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Points Card View

public struct PointsCard: View {
    @ObservedObject var store: PointsStore

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: store.level.icon)
                            .foregroundStyle(Color.accentColor)
                            .font(.title2)
                        Text(store.level.name)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                    }
                    Text("\(store.totalPoints) pts")
                        .font(.system(.title, design: .rounded, weight: .heavy))
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                if store.currentStreak >= 2 {
                    VStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        Text("\(store.currentStreak)")
                            .font(.headline.bold())
                            .foregroundStyle(.orange)
                        Text("streak")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Progress bar to next level
            if let next = store.nextLevel {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Next: \(next.name)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(next.minPoints - store.totalPoints) pts away")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentColor)
                                .frame(width: geo.size.width * store.levelProgress)
                                .animation(.spring(response: 0.6), value: store.levelProgress)
                        }
                    }
                    .frame(height: 8)
                }
            }

            // Recent events
            if !store.recentEvents.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Array(store.recentEvents.prefix(3).enumerated()), id: \.offset) { _, entry in
                        HStack(spacing: 8) {
                            Image(systemName: entry.event.icon)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 18)
                            Text(entry.event.label).font(.caption)
                            Spacer()
                            Text("+\(entry.event.points)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
        .cardStyle()
    }
}
