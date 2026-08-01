import SwiftUI

// MARK: - Calendar Heatmap

public struct CalendarHeatmap: View {

    public enum Mode {
        case doctor
        case hospital
    }

    public struct DayData: Identifiable, Hashable {
        public let id = UUID()
        public let date: Date
        public let urgencyValue: Double
        public let shiftCount: Int
        public let isPast: Bool
        public var isFilledByOthers: Bool = false
        public var isHospitalUnavailable: Bool = false
        /// Hospital mode: green = all filled, yellow = partial, red = none filled.
        public var coverageFillLevel: CoverageFillLevel? = nil

        public enum CoverageFillLevel: Hashable {
            case allFilled
            case partial
            case noneFilled
        }

        public init(
            date: Date, urgencyValue: Double, shiftCount: Int, isPast: Bool,
            isFilledByOthers: Bool = false, isHospitalUnavailable: Bool = false,
            coverageFillLevel: CoverageFillLevel? = nil
        ) {
            self.date = date
            self.urgencyValue = urgencyValue
            self.shiftCount = shiftCount
            self.isPast = isPast
            self.isFilledByOthers = isFilledByOthers
            self.isHospitalUnavailable = isHospitalUnavailable
            self.coverageFillLevel = coverageFillLevel
        }
    }

    private let month: Date
    private let data: [Date: DayData]
    private let mode: Mode
    private let embedded: Bool
    private let onSelect: (Date) -> Void
    @Binding private var hoverDate: Date?

    public init(
        month: Date,
        dayData: [DayData],
        mode: Mode = .hospital,
        embedded: Bool = false,
        hoverDate: Binding<Date?> = .constant(nil),
        onSelect: @escaping (Date) -> Void
    ) {
        self.month = month.startOfMonth()
        self.data = Dictionary(uniqueKeysWithValues: dayData.map { ($0.date.onlyDate(), $0) })
        self.mode = mode
        self.embedded = embedded
        self._hoverDate = hoverDate
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(month, format: .dateTime.month(.wide).year())
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 2)

            let daysOfWeek = ["S", "M", "T", "W", "T", "F", "S"]
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Text(daysOfWeek[index])
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Brand.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }

            let days = generateDaysForMonth()
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(days, id: \.self) { date in
                    if let date = date {
                        dayCell(for: date)
                    } else {
                        Color.clear.aspectRatio(1.0, contentMode: .fit)
                    }
                }
            }
        }
        .modifier(CalendarChrome(embedded: embedded))
    }

    @ViewBuilder
    private func dayCell(for date: Date) -> some View {
        let dData = data[date.onlyDate()] ?? DayData(date: date, urgencyValue: 1000, shiftCount: 0, isPast: false)
        let isInMonth = Calendar.current.isInSameMonthAs(date, month)
        let shouldDisableClick = mode == .doctor && (dData.isFilledByOthers || dData.isHospitalUnavailable)
        let isDimmed = dData.isFilledByOthers || dData.isHospitalUnavailable
        let showUnavailableX = dData.isHospitalUnavailable
        let isHovered = mode == .hospital &&
            Calendar.current.isDate(hoverDate ?? .distantPast, inSameDayAs: date)

        Button {
            if !shouldDisableClick { onSelect(date) }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(heatmapColor(for: dData, isInMonth: isInMonth))
                    .aspectRatio(1.0, contentMode: .fit)
                    .overlay {
                        if isHovered {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
                        }
                    }

                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isInMonth ? Brand.textPrimary : Brand.textTertiary)

                if showUnavailableX {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle().fill(Brand.danger.opacity(0.9)).frame(width: 16, height: 16)
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundStyle(.white)
                            }
                            .padding(4)
                        }
                        Spacer()
                    }
                } else if mode == .doctor && dData.isFilledByOthers {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "person.fill")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Brand.textTertiary)
                                .padding(5)
                        }
                        Spacer()
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(shouldDisableClick)
        .opacity(isDimmed ? 0.35 : 1.0)
        .scaleEffect(isHovered ? 1.12 : 1.0)
        .zIndex(isHovered ? 1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: hoverDate)
        .onHover { hovering in
            guard mode == .hospital else { return }
            hoverDate = hovering ? date.onlyDate() : (Calendar.current.isDate(hoverDate ?? .distantPast, inSameDayAs: date) ? nil : hoverDate)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    guard mode == .hospital else { return }
                    hoverDate = date.onlyDate()
                }
        )
    }

    private func generateDaysForMonth() -> [Date?] {
        let cal = Calendar.current
        guard let monthRange = cal.range(of: .day, in: .month, for: month) else { return [] }
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let firstOfMonth = cal.date(from: comps) else { return [] }

        let offsetDays = cal.component(.weekday, from: firstOfMonth) - 1
        var days: [Date?] = Array(repeating: nil, count: offsetDays)
        for day in 1...monthRange.count {
            if let date = cal.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                days.append(date)
            }
        }
        return days
    }

    private func heatmapColor(for d: DayData, isInMonth: Bool) -> Color {
        if d.isHospitalUnavailable {
            return Color.white.opacity(isInMonth ? 0.06 : 0.03)
        }
        if d.isPast { return Color.white.opacity(0.04) }

        switch mode {
        case .doctor:
            if d.shiftCount == 0 {
                return Color.white.opacity(isInMonth ? 0.04 : 0.02)
            }
            let hours = d.urgencyValue
            switch hours {
            case ..<12:   return Color(hex: "EF4444").opacity(0.6)
            case 12..<24: return Color(hex: "F97316").opacity(0.55)
            case 24..<48: return Color(hex: "EAB308").opacity(0.45)
            default:      return Color(hex: "22C55E").opacity(0.4)
            }
        case .hospital:
            if let level = d.coverageFillLevel {
                switch level {
                case .allFilled:  return Color(hex: "22C55E").opacity(isInMonth ? 0.55 : 0.3)
                case .partial:   return Color(hex: "EAB308").opacity(isInMonth ? 0.55 : 0.3)
                case .noneFilled: return Color(hex: "EF4444").opacity(isInMonth ? 0.55 : 0.3)
                }
            }
            return Color.white.opacity(isInMonth ? 0.04 : 0.02)
        }
    }
}

// MARK: - Day legend

struct CalendarDayLegend: View {
    var showHospitalHint: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            if showHospitalHint {
                legendSwatch(color: Color(hex: "22C55E"), label: "All filled")
                legendSwatch(color: Color(hex: "EAB308"), label: "Partial")
                legendSwatch(color: Color(hex: "EF4444"), label: "None filled")
                legendItem(icon: "xmark.circle.fill", color: Brand.danger, label: "Blocked")
            } else {
                legendItem(icon: "person.fill", color: Brand.textTertiary, label: "Filled")
                legendItem(icon: "xmark.circle.fill", color: Brand.danger, label: "Closed")
            }
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(Brand.textSecondary)
    }

    private func legendSwatch(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color.opacity(0.55))
                .frame(width: 12, height: 12)
            Text(label)
        }
    }

    private func legendItem(icon: String, color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color).font(.caption2)
            Text(label)
        }
    }
}

// MARK: - Optional outer chrome

private struct CalendarChrome: ViewModifier {
    let embedded: Bool

    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content
                .padding(Brand.cardPadding)
                .background(Brand.surface, in: RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                        .strokeBorder(Brand.border, lineWidth: 1)
                )
        }
    }
}
