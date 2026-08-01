import Foundation

// MARK: - Holiday Calendar

public struct HolidayCalendar {

    public struct Holiday: Equatable {
        public let name: String
        public let premium: Double   // e.g. 0.10 = 10%
    }

    // Only real, important holidays — no "National Donut Day" nonsense
    private static let premiumHolidays: [Holiday] = [
        Holiday(name: "Christmas Day",      premium: 0.10),
        Holiday(name: "Christmas Eve",      premium: 0.07),
        Holiday(name: "Thanksgiving",       premium: 0.10),
        Holiday(name: "Easter Sunday",      premium: 0.10),
        Holiday(name: "New Year's Day",     premium: 0.07),
        Holiday(name: "New Year's Eve",     premium: 0.05),
        Holiday(name: "Independence Day",   premium: 0.10),
        Holiday(name: "Memorial Day",       premium: 0.05),
        Holiday(name: "Labor Day",          premium: 0.05),
    ]

    /// Returns the holiday (if any) that applies to a given date.
    public static func holiday(on date: Date) -> Holiday? {
        let cal = Calendar.current
        let year  = cal.component(.year,  from: date)
        let month = cal.component(.month, from: date)
        let day   = cal.component(.day,   from: date)

        // Fixed-date holidays
        switch (month, day) {
        case (12, 25): return holiday(named: "Christmas Day")
        case (12, 24): return holiday(named: "Christmas Eve")
        case (12, 31): return holiday(named: "New Year's Eve")
        case (1,  1):  return holiday(named: "New Year's Day")
        case (7,  4):  return holiday(named: "Independence Day")
        default: break
        }

        // Floating holidays
        if isEaster(month: month, day: day, year: year)    { return holiday(named: "Easter Sunday") }
        if isThanksgiving(date: date, cal: cal)             { return holiday(named: "Thanksgiving") }
        if isMemorialDay(date: date, cal: cal)              { return holiday(named: "Memorial Day") }
        if isLaborDay(date: date, cal: cal)                 { return holiday(named: "Labor Day") }

        return nil
    }

    public static func premiumMultiplier(on date: Date) -> Double {
        1.0 + (holiday(on: date)?.premium ?? 0.0)
    }

    // MARK: - Private helpers

    private static func holiday(named name: String) -> Holiday? {
        premiumHolidays.first { $0.name == name }
    }

    // Anonymous Gregorian algorithm for Easter
    private static func isEaster(month: Int, day: Int, year: Int) -> Bool {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let easterMonth = (h + l - 7 * m + 114) / 31
        let easterDay   = ((h + l - 7 * m + 114) % 31) + 1
        return month == easterMonth && day == easterDay
    }

    // Thanksgiving = 4th Thursday of November
    private static func isThanksgiving(date: Date, cal: Calendar) -> Bool {
        let comps = cal.dateComponents([.month, .weekday, .weekdayOrdinal], from: date)
        return comps.month == 11 && comps.weekday == 5 && comps.weekdayOrdinal == 4
    }

    // Memorial Day = last Monday of May
    private static func isMemorialDay(date: Date, cal: Calendar) -> Bool {
        guard cal.component(.month, from: date) == 5,
              cal.component(.weekday, from: date) == 2 else { return false }
        // Check if next Monday is in June
        let nextWeek = cal.date(byAdding: .day, value: 7, to: date)!
        return cal.component(.month, from: nextWeek) == 6
    }

    // Labor Day = first Monday of September
    private static func isLaborDay(date: Date, cal: Calendar) -> Bool {
        let comps = cal.dateComponents([.month, .weekday, .weekdayOrdinal], from: date)
        return comps.month == 9 && comps.weekday == 2 && comps.weekdayOrdinal == 1
    }
}
