import SwiftUI
import UIKit

// MARK: - Calendar Heatmap

public struct CalendarHeatmap: View {

    public enum Mode {
        case doctor
        case hospital
    }

    public struct DayData: Identifiable, Hashable {
        public var id: Date { date }
        public let date: Date
        public let urgencyValue: Double
        public let shiftCount: Int
        public let isPast: Bool
        public var isFilledByOthers: Bool = false
        public var isHospitalUnavailable: Bool = false
        /// Doctor mode: the current doctor already holds a shift this day.
        public var isMyScheduledDay: Bool = false
        /// Hospital mode: green = all filled, yellow = partial, red = none filled.
        public var coverageFillLevel: CoverageFillLevel? = nil
        /// Doctor mode: going rate for the doctor's specialty that day (shown under the day number).
        public var goingRate: Double? = nil

        public enum CoverageFillLevel: Hashable {
            case allFilled
            case partial
            case noneFilled
        }

        public init(
            date: Date, urgencyValue: Double, shiftCount: Int, isPast: Bool,
            isFilledByOthers: Bool = false, isHospitalUnavailable: Bool = false,
            isMyScheduledDay: Bool = false,
            coverageFillLevel: CoverageFillLevel? = nil,
            goingRate: Double? = nil
        ) {
            self.date = date.onlyDate()
            self.urgencyValue = urgencyValue
            self.shiftCount = shiftCount
            self.isPast = isPast
            self.isFilledByOthers = isFilledByOthers
            self.isHospitalUnavailable = isHospitalUnavailable
            self.isMyScheduledDay = isMyScheduledDay
            self.coverageFillLevel = coverageFillLevel
            self.goingRate = goingRate
        }

        var isFullyCovered: Bool { coverageFillLevel == .allFilled }
        var needsCoverage: Bool {
            switch coverageFillLevel {
            case .noneFilled, .partial: return true
            default: return false
            }
        }
    }

    private let month: Date
    private let data: [Date: DayData]
    private let mode: Mode
    private let embedded: Bool
    /// When true (Alter Shifts), tap selects the day immediately instead of quick-view.
    private let tapSelectsDay: Bool
    /// Hospital dashboard: grey full days, rose open days, bubble-pop filled away.
    private let focusOpenDays: Bool
    private let onSelect: (Date) -> Void
    @Binding private var hoverDate: Date?

    @State private var focusPhase: FocusPhase = .idle
    @Namespace private var gapsNamespace

    private enum FocusPhase: Equatable {
        case idle
        case styling      // full→grey, open→rose
        case bubbling     // filled lift + green glow
        case popping      // filled scale to 0
        case compacted    // open days reflow + grow
    }

    public init(
        month: Date,
        dayData: [DayData],
        mode: Mode = .hospital,
        embedded: Bool = false,
        tapSelectsDay: Bool = false,
        hoverDate: Binding<Date?> = .constant(nil),
        focusOpenDays: Bool = false,
        onSelect: @escaping (Date) -> Void
    ) {
        self.month = month.startOfMonth()
        self.data = Dictionary(uniqueKeysWithValues: dayData.map { ($0.date.onlyDate(), $0) })
        self.mode = mode
        self.embedded = embedded
        self.tapSelectsDay = tapSelectsDay
        self.focusOpenDays = focusOpenDays
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
                        .opacity(focusPhase == .compacted ? 0.35 : 1)
                }
            }

            if focusPhase == .compacted {
                compactedOpenGrid
                    .transition(.opacity)
            } else {
                monthGrid
            }
        }
        .modifier(CalendarChrome(embedded: embedded))
        .onChange(of: focusOpenDays) { _, on in
            if on {
                runFocusOnSequence()
            } else {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    focusPhase = .idle
                }
            }
        }
        .onChange(of: month) { _, _ in
            if focusOpenDays {
                focusPhase = .compacted
            } else {
                focusPhase = .idle
            }
        }
        .onAppear {
            if focusOpenDays { focusPhase = .compacted }
        }
    }

    // MARK: - Grids

    private var monthGrid: some View {
        let days = generateDaysForMonth()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(for: date, compact: false)
                } else {
                    Color.clear.aspectRatio(1.0, contentMode: .fit)
                }
            }
        }
    }

    private var compactedOpenGrid: some View {
        let openDays = openCoverageDates()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

        return Group {
            if openDays.isEmpty {
                Text("No open days this month — coverage looks complete.")
                    .font(.subheadline)
                    .foregroundStyle(Brand.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(openDays, id: \.self) { date in
                        dayCell(for: date, compact: true)
                            .matchedGeometryEffect(id: date.onlyDate(), in: gapsNamespace)
                    }
                }
            }
        }
    }

    private func openCoverageDates() -> [Date] {
        generateDaysForMonth().compactMap { date -> Date? in
            guard let date else { return nil }
            guard Calendar.current.isInSameMonthAs(date, month) else { return nil }
            return remainsInFocus(data[date.onlyDate()]) ? date.onlyDate() : nil
        }
    }

    /// The days that stay (and reflow) once the focus filter completes.
    private func remainsInFocus(_ d: DayData?) -> Bool {
        switch mode {
        case .hospital:
            guard let d else { return true }
            if d.isHospitalUnavailable { return false }
            if d.isFullyCovered { return false }
            if d.isPast, !d.needsCoverage { return false }
            return true
        case .doctor:
            guard let d else { return false }
            if d.isPast { return false }
            if d.isHospitalUnavailable { return false }
            if d.isMyScheduledDay { return false }
            if d.isFilledByOthers { return false }
            return d.shiftCount > 0
        }
    }

    /// The days that bubble + pop away when focusing (they're already handled).
    private func popsAwayInFocus(_ d: DayData) -> Bool {
        switch mode {
        case .hospital: return d.isFullyCovered
        case .doctor:   return d.isMyScheduledDay
        }
    }

    // MARK: - Focus animation

    private func runFocusOnSequence() {
        hoverDate = nil
        focusPhase = .styling
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) {
                focusPhase = .bubbling
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                focusPhase = .popping
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                focusPhase = .compacted
            }
        }
    }

    // MARK: - Day cell

    @ViewBuilder
    private func dayCell(for date: Date, compact: Bool) -> some View {
        let dData = data[date.onlyDate()] ?? DayData(date: date, urgencyValue: 1000, shiftCount: 0, isPast: false)
        let isInMonth = Calendar.current.isInSameMonthAs(date, month)
        let shouldDisableClick = mode == .doctor && (dData.isFilledByOthers || dData.isHospitalUnavailable)
        let isDimmed = dData.isFilledByOthers || dData.isHospitalUnavailable
        let showUnavailableX = dData.isHospitalUnavailable
        let isHovered =
            Calendar.current.isDate(hoverDate ?? .distantPast, inSameDayAs: date)
        let inFocusFlow = focusOpenDays
        let isFilled = popsAwayInFocus(dData)
        let remains = remainsInFocus(dData)

        let filledTransform = filledMotion(isFilled: isFilled, inFocusFlow: inFocusFlow)
        let openScale: CGFloat = {
            guard inFocusFlow, remains else { return compact ? 1.06 : 1.0 }
            switch focusPhase {
            case .styling: return 1.0
            case .bubbling, .popping: return 1.04
            case .compacted: return 1.08
            case .idle: return 1.0
            }
        }()

        let cell = ZStack {
                RoundedRectangle(cornerRadius: compact ? 10 : 8, style: .continuous)
                    .fill(heatmapColor(for: dData, isInMonth: isInMonth, inFocusFlow: inFocusFlow))
                    .aspectRatio(1.0, contentMode: .fit)
                    .overlay {
                        RoundedRectangle(cornerRadius: compact ? 10 : 8, style: .continuous)
                            .strokeBorder(cellBorder(for: dData, inFocusFlow: inFocusFlow, isHovered: isHovered), lineWidth: isHovered ? 2 : 1)
                    }
                    .shadow(
                        color: filledBubbleGlow(isFilled: isFilled, inFocusFlow: inFocusFlow),
                        radius: focusPhase == .bubbling && isFilled ? 10 : 0,
                        y: focusPhase == .bubbling && isFilled ? -2 : 0
                    )

                VStack(spacing: 1) {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.system(size: compact ? 13 : 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(dayTextColor(for: dData, isInMonth: isInMonth, inFocusFlow: inFocusFlow))
                    if mode == .doctor, isInMonth, let rate = dData.goingRate, rate > 0 {
                        Text(Self.compactGoingRate(rate))
                            .font(.system(size: compact ? 8 : 7, weight: .bold, design: .rounded))
                            .foregroundStyle(dayTextColor(for: dData, isInMonth: isInMonth, inFocusFlow: inFocusFlow).opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                }

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
            .contentShape(Rectangle())

        let gesturesDisabled = shouldDisableClick
            || (inFocusFlow && isFilled && focusPhase != .idle && focusPhase != .styling)

        cell
        .opacity(isDimmed ? 0.35 : filledTransform.opacity)
        .scaleEffect((isHovered ? 1.12 : 1.0) * filledTransform.scale * openScale)
        .offset(y: filledTransform.offsetY)
        .zIndex(isHovered || (inFocusFlow && isFilled && focusPhase == .bubbling) ? 2 : 0)
        .modifier(GapsMatchIfNeeded(
            enabled: inFocusFlow && remains,
            id: date.onlyDate(),
            namespace: gapsNamespace,
            isSource: focusPhase != .compacted
        ))
        .animation(.easeOut(duration: 0.15), value: hoverDate)
        .onHover { hovering in
            guard mode == .hospital, !(inFocusFlow && isFilled) else { return }
            hoverDate = hovering ? date.onlyDate() : (Calendar.current.isDate(hoverDate ?? .distantPast, inSameDayAs: date) ? nil : hoverDate)
        }
        .gesture(
            LongPressGesture(minimumDuration: 0.4, maximumDistance: 12)
                .onEnded { _ in
                    guard !gesturesDisabled else { return }
                    handleDayLongPress(
                        date: date,
                        shouldDisableClick: shouldDisableClick,
                        inFocusFlow: inFocusFlow,
                        isFilled: isFilled
                    )
                }
                .exclusively(before:
                    TapGesture()
                        .onEnded {
                            guard !gesturesDisabled else { return }
                            handleDayTap(date: date)
                        }
                )
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityHidden(inFocusFlow && isFilled && (focusPhase == .popping || focusPhase == .compacted))
    }

    private func handleDayTap(date: Date) {
        if mode == .hospital && !tapSelectsDay {
            hoverDate = Calendar.current.isDate(hoverDate ?? .distantPast, inSameDayAs: date) ? nil : date.onlyDate()
        } else if mode == .doctor {
            hoverDate = nil
            onSelect(date)
        } else {
            onSelect(date)
        }
    }

    private func handleDayLongPress(
        date: Date,
        shouldDisableClick: Bool,
        inFocusFlow: Bool,
        isFilled: Bool
    ) {
        if mode == .doctor {
            guard !shouldDisableClick else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeOut(duration: 0.18)) {
                hoverDate = Calendar.current.isDate(hoverDate ?? .distantPast, inSameDayAs: date)
                    ? nil
                    : date.onlyDate()
            }
            return
        }
        guard mode == .hospital, !tapSelectsDay else { return }
        guard !(inFocusFlow && isFilled) else { return }
        onSelect(date)
    }

    /// Compact rate for calendar cells (e.g. $1.2k, $850).
    private static func compactGoingRate(_ rate: Double) -> String {
        if rate >= 10_000 {
            return "$\(Int((rate / 1000).rounded()))k"
        }
        if rate >= 1000 {
            let k = rate / 1000
            if abs(k - k.rounded()) < 0.05 {
                return "$\(Int(k.rounded()))k"
            }
            return String(format: "$%.1fk", k)
        }
        return "$\(Int(rate.rounded()))"
    }

    private func filledMotion(isFilled: Bool, inFocusFlow: Bool) -> (scale: CGFloat, offsetY: CGFloat, opacity: Double) {
        guard inFocusFlow, isFilled else { return (1, 0, 1) }
        switch focusPhase {
        case .idle:
            return (1, 0, 1)
        case .styling:
            return (1, 0, 1)
        case .bubbling:
            return (1.18, -10, 1)
        case .popping:
            return (0.01, -4, 0)
        case .compacted:
            return (0.01, 0, 0)
        }
    }

    private func filledBubbleGlow(isFilled: Bool, inFocusFlow: Bool) -> Color {
        guard inFocusFlow, isFilled, focusPhase == .bubbling else { return .clear }
        return Color(hex: "22C55E").opacity(0.55)
    }

    // MARK: - Colors (professional rose, not alarm red)

    private func heatmapColor(for d: DayData, isInMonth: Bool, inFocusFlow: Bool) -> Color {
        if d.isHospitalUnavailable {
            return Color.white.opacity(isInMonth ? 0.06 : 0.03)
        }
        if d.isPast && !inFocusFlow { return Color.white.opacity(0.04) }

        if inFocusFlow, mode == .hospital {
            if d.isFullyCovered {
                // Soft slate grey — filled days that will pop away
                return Color(hex: "CBD5E1").opacity(isInMonth ? 0.55 : 0.28)
            }
            if d.needsCoverage {
                // Dusty rose wash — calm, clinical, readable
                return Color(hex: "FFE4E6").opacity(isInMonth ? 0.95 : 0.5)
            }
            return Color(hex: "F1F5F9").opacity(0.8)
        }

        if inFocusFlow, mode == .doctor, d.isMyScheduledDay {
            // Your booked day — glows green, then bubbles away.
            return Color(hex: "22C55E").opacity(isInMonth ? 0.5 : 0.28)
        }

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

    private func cellBorder(for d: DayData, inFocusFlow: Bool, isHovered: Bool) -> Color {
        if isHovered { return Color.white.opacity(0.85) }
        if inFocusFlow, d.needsCoverage {
            return Color(hex: "E11D48").opacity(0.22)
        }
        if inFocusFlow, d.isFullyCovered {
            return Color(hex: "94A3B8").opacity(0.35)
        }
        return .clear
    }

    private func dayTextColor(for d: DayData, isInMonth: Bool, inFocusFlow: Bool) -> Color {
        if !isInMonth { return Brand.textTertiary }
        if inFocusFlow, d.isFullyCovered {
            return Brand.textTertiary
        }
        if inFocusFlow, d.needsCoverage {
            return Color(hex: "9F1239") // deep rose, not neon
        }
        return Brand.textPrimary
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

private struct GapsMatchIfNeeded: ViewModifier {
    let enabled: Bool
    let id: Date
    let namespace: Namespace.ID
    let isSource: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.matchedGeometryEffect(id: id, in: namespace, isSource: isSource)
        } else {
            content
        }
    }
}
