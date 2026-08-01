import Foundation

extension Date {
    /// Normalized to start-of-day for calendar dictionary keys.
    func onlyDate() -> Date {
        Calendar.current.startOfDay(for: self)
    }

    /// First day of this date's month at start-of-day.
    func startOfMonth() -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: self)
        return cal.date(from: comps) ?? self
    }
}

extension Calendar {
    func isInSameMonthAs(_ date1: Date, _ date2: Date) -> Bool {
        let c1 = dateComponents([.year, .month], from: date1)
        let c2 = dateComponents([.year, .month], from: date2)
        return c1.year == c2.year && c1.month == c2.month
    }
}

// MARK: - Policy lead-time display (>72h → days → weeks → months)

enum PolicyLeadTimeFormatter {
    /// Maximum lead time selectable in policy UI (3 calendar months ≈ 90 days).
    static let maxPolicyHours = 90 * 24

    /// Formats hours for on-call policy UI. Up to 72h stays in hours; beyond that uses days, weeks, or months.
    static func format(hours: Int) -> String {
        guard hours > 0 else { return "0h" }
        guard hours > 72 else { return "\(hours)h" }

        let days = Double(hours) / 24.0
        if days < 14 {
            return pluralized(Int(days.rounded()), singular: "day", plural: "days")
        }

        let weeks = days / 7.0
        if weeks < 8 {
            return pluralized(max(1, Int(weeks.rounded())), singular: "week", plural: "weeks")
        }

        let months = days / 30.0
        return pluralized(max(1, Int(months.rounded())), singular: "month", plural: "months")
    }

    static func withinLabel(hours: Int) -> String {
        "Within \(format(hours: hours))"
    }

    static func beforeStartLabel(hours: Int) -> String {
        "\(format(hours: hours)) before start"
    }

    static func beforeShiftLabel(hours: Int) -> String {
        "\(format(hours: hours)) before shift"
    }

    private static func pluralized(_ count: Int, singular: String, plural: String) -> String {
        count == 1 ? "1 \(singular)" : "\(count) \(plural)"
    }

    static func formatSliderHours(_ hours: Int) -> String {
        format(hours: min(maxPolicyHours, max(0, hours)))
    }
}
