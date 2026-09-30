import SwiftUI
import Charts

// MARK: - Period model (month vs year — never mixed)

enum FinanceGrain: String, CaseIterable, Identifiable {
    case month, year
    var id: String { rawValue }
    var title: String { self == .month ? "Month" : "Year" }
}

struct FinancePeriod: Hashable, Identifiable {
    let grain: FinanceGrain
    /// For months: year + month. For years: year only (month ignored).
    let year: Int
    let month: Int

    var id: String {
        grain == .year ? "y\(year)" : "m\(year)-\(month)"
    }

    var shortLabel: String {
        if grain == .year {
            return "'\(year % 100)"
        }
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let m = min(12, max(1, month))
        return "\(names[m - 1]) '\(year % 100)"
    }

    var menuLabel: String {
        if grain == .year { return "'\(year % 100)" }
        let names = ["January", "February", "March", "April", "May", "June",
                     "July", "August", "September", "October", "November", "December"]
        return "\(names[min(12, max(1, month)) - 1]) '\(year % 100)"
    }

    static func currentMonth(from date: Date = Date()) -> FinancePeriod {
        let c = Calendar.current
        return FinancePeriod(grain: .month, year: c.component(.year, from: date), month: c.component(.month, from: date))
    }

    static func currentYear(from date: Date = Date()) -> FinancePeriod {
        FinancePeriod(grain: .year, year: Calendar.current.component(.year, from: date), month: 1)
    }
}

// MARK: - Deterministic mock finance series

enum FinanceMockData {
    /// Stable pseudo-random 0…1 from string.
    static func unit(_ seed: String) -> Double {
        var h: UInt64 = 5381
        for u in seed.unicodeScalars { h = ((h << 5) &+ h) &+ UInt64(u.value) }
        return Double(h % 10_000) / 10_000.0
    }

    /// Hospital billing committed payout for a period.
    static func hospitalBilling(period: FinancePeriod, hospitalName: String) -> Double {
        let base = 48_000.0 + unit("bill-\(hospitalName)-\(period.id)") * 92_000
        if period.grain == .year {
            return base * (9.5 + unit("y-\(period.id)") * 3.5)
        }
        let season = 0.82 + 0.28 * sin(Double(period.month) / 12.0 * .pi * 2)
        return base * season
    }

    /// Doctor "stock" earnings index for a period (looks like a price series when charted).
    static func doctorIndex(period: FinancePeriod, doctorName: String, specialty: String) -> Double {
        let base = 820.0 + unit("doc-\(doctorName)-\(specialty)") * 1_400
        if period.grain == .year {
            let trend = Double(period.year - 2024) * (40 + unit("yt-\(doctorName)") * 80)
            return base * 11 + trend
        }
        let wave = sin(Double(period.month + Int(unit("ph-\(doctorName)") * 6)) / 12.0 * .pi * 2)
        let drift = Double(period.year - 2024) * 18 + Double(period.month) * 2.2
        return base + wave * 90 + drift + unit("n-\(period.id)-\(doctorName)") * 55
    }

    /// Specialty index = average of its doctors' indexes for the period.
    static func specialtyIndex(period: FinancePeriod, specialty: String, doctorNames: [String]) -> Double {
        let names = doctorNames.isEmpty ? [specialty] : doctorNames
        let sum = names.reduce(0.0) { partial, name in
            partial + doctorIndex(period: period, doctorName: name, specialty: specialty)
        }
        return sum / Double(names.count)
    }

    static func availableYears(around now: Date = Date(), past: Int = 3, future: Int = 3) -> [Int] {
        let y = Calendar.current.component(.year, from: now)
        return Array((y - past)...(y + future))
    }

    static func monthPeriods(years: [Int]) -> [FinancePeriod] {
        years.flatMap { y in
            (1...12).map { FinancePeriod(grain: .month, year: y, month: $0) }
        }.reversed()
    }

    static func yearPeriods(years: [Int]) -> [FinancePeriod] {
        years.map { FinancePeriod(grain: .year, year: $0, month: 1) }.reversed()
    }

    /// Series of points for a single selection (last 12 months or last N years).
    static func timeline(for grain: FinanceGrain, endingAt end: FinancePeriod, count: Int) -> [FinancePeriod] {
        switch grain {
        case .month:
            var out: [FinancePeriod] = []
            var y = end.year
            var m = end.month
            for _ in 0..<count {
                out.append(FinancePeriod(grain: .month, year: y, month: m))
                m -= 1
                if m < 1 { m = 12; y -= 1 }
            }
            return out.reversed()
        case .year:
            return (0..<count).map { FinancePeriod(grain: .year, year: end.year - (count - 1 - $0), month: 1) }
        }
    }
}

/// Posted shift rates from the server. Explore is the only place that invents figures.
private enum HospitalEarnings {
    static var usesGenerated: Bool { InvestorDemo.usesLocalSampleData }

    static func filled(hospitalID: UUID?) -> [AssignedShiftsStore.AssignedShift] {
        guard let hospitalID else { return [] }
        return AssignedShiftsStore.shared.assignedShifts.filter {
            $0.shift.hospitalID == hospitalID
                && $0.status != .canceled
                && $0.doctorID != AssignedShiftsStore.coveredBySomeoneElse
        }
    }

    static func contains(_ date: Date, _ period: FinancePeriod) -> Bool {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        if period.grain == .year { return year == period.year }
        return year == period.year && calendar.component(.month, from: date) == period.month
    }

    /// The rate stored on the shift. Hourly shifts are the floor times the posted hours.
    static func committed(_ shift: Shift) -> Double {
        if shift.rateUnit == .perHour {
            return shift.rateFloor * Double(max(shift.durationHours, 1))
        }
        return shift.rateFloor
    }

    static func hospitalTotal(hospitalID: UUID?, period: FinancePeriod) -> Double {
        filled(hospitalID: hospitalID)
            .filter { contains($0.shift.date, period) }
            .reduce(0) { $0 + committed($1.shift) }
    }

    static func doctorTotal(hospitalID: UUID?, doctorID: UUID, period: FinancePeriod) -> Double {
        filled(hospitalID: hospitalID)
            .filter { $0.doctorID == doctorID && contains($0.shift.date, period) }
            .reduce(0) { $0 + committed($1.shift) }
    }

    static func specialtyTotal(hospitalID: UUID?, specialty: String, doctorIDs: [UUID], period: FinancePeriod) -> Double {
        let ids = Set(doctorIDs)
        return filled(hospitalID: hospitalID)
            .filter { ids.contains($0.doctorID) && $0.shift.specialty == specialty && contains($0.shift.date, period) }
            .reduce(0) { $0 + committed($1.shift) }
    }
}

struct FinanceSeriesPoint: Identifiable {
    let id: String
    let period: FinancePeriod
    let seriesKey: String
    let value: Double
}

// MARK: - Shared period chrome (dropdowns + compare)

struct FinancePeriodChrome: View {
    @Binding var grain: FinanceGrain
    @Binding var primary: FinancePeriod
    @Binding var compareEnabled: Bool
    @Binding var compared: Set<FinancePeriod>

    /// Double-tap a year in year-compare to reveal that year’s months.
    @State private var expandedYear: Int? = nil
    @State private var pendingYearTap: DispatchWorkItem? = nil

    private var years: [Int] { FinanceMockData.availableYears() }
    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    /// Month compare chips: Jan–Dec of the current year only.
    private var currentYearMonths: [FinancePeriod] {
        (1...12).map { FinancePeriod(grain: .month, year: currentYear, month: $0) }
    }

    private var yearOptions: [FinancePeriod] {
        FinanceMockData.yearPeriods(years: years)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                ForEach(FinanceGrain.allCases) { g in
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            grain = g
                            compared.removeAll()
                            primary = g == .year
                                ? FinancePeriod.currentYear()
                                : FinancePeriod.currentMonth()
                            compareEnabled = false
                            expandedYear = nil
                        }
                    } label: {
                        Text(g.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(grain == g ? .white : Brand.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background {
                                if grain == g {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Brand.accentGradient)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            HStack(spacing: 10) {
                periodMenu
                Spacer(minLength: 8)
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        compareEnabled.toggle()
                        expandedYear = nil
                        if !compareEnabled {
                            compared.removeAll()
                        } else {
                            compared.insert(primary)
                        }
                    }
                } label: {
                    Label(compareEnabled ? "Comparing" : "Compare", systemImage: compareEnabled ? "checkmark.circle.fill" : "arrow.left.arrow.right")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(compareEnabled ? .white : Brand.accent)
                        .background(
                            compareEnabled ? Brand.accent : Brand.accentSoft,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }

            if compareEnabled {
                if grain == .month {
                    Text("Months shown are Jan–Dec '\(String(format: "%02d", currentYear % 100)) only. For other years: switch to Year → double-tap a year → pick its months.")
                        .font(.caption)
                        .foregroundStyle(Brand.textTertiary)

                    compareChipRow(options: currentYearMonths) { toggleCompare($0) }
                } else {
                    Text("Tap a year to compare years. Double-tap a year to expand its months, then tap months to compare month-to-month.")
                        .font(.caption)
                        .foregroundStyle(Brand.textTertiary)

                    yearCompareRow

                    if let expandedYear {
                        Text("'\(String(format: "%02d", expandedYear % 100)) months — tap to add")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.textSecondary)
                            .padding(.top, 4)

                        let months = (1...12).map { FinancePeriod(grain: .month, year: expandedYear, month: $0) }
                        compareChipRow(options: months) { month in
                            selectMonthFromExpandedYear(month)
                        }
                    }
                }
            }

            if compareEnabled && !compared.isEmpty {
                let labels = compared
                    .filter { $0.grain == grain || grain == .month }
                    .sorted { $0.id < $1.id }
                    .map(\.shortLabel)
                if !labels.isEmpty {
                    Text(labels.joined(separator: " · "))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Brand.textSecondary)
                }
            }
        }
        .cardStyle()
    }

    // MARK: Rows

    private var yearCompareRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(yearOptions) { option in
                    let on = compared.contains(option) || (primary.grain == .year && primary.year == option.year)
                    let expanded = expandedYear == option.year
                    Text(option.shortLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .foregroundStyle(expanded || on ? .white : Brand.textPrimary)
                        .background(
                            expanded ? Brand.accentAlt : (on ? Brand.accent : Brand.surfaceHigh),
                            in: Capsule()
                        )
                        .overlay(Capsule().strokeBorder(Brand.border, lineWidth: (expanded || on) ? 0 : 1))
                        .onTapGesture(count: 2) {
                            pendingYearTap?.cancel()
                            pendingYearTap = nil
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                                if expandedYear == option.year {
                                    expandedYear = nil
                                } else {
                                    expandedYear = option.year
                                    compared = Set(compared.filter { $0.grain == .month })
                                }
                            }
                        }
                        .onTapGesture(count: 1) {
                            pendingYearTap?.cancel()
                            let year = option.year
                            let work = DispatchWorkItem {
                                // Ignore if this tap became part of a double-tap expand
                                guard expandedYear != year else { return }
                                toggleCompare(option)
                            }
                            pendingYearTap = work
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
                        }
                }
            }
        }
    }

    private func compareChipRow(options: [FinancePeriod], onTap: @escaping (FinancePeriod) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    let on = compared.contains(option) || option == primary
                    Button {
                        onTap(option)
                    } label: {
                        Text(option.shortLabel)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .foregroundStyle(on ? .white : Brand.textPrimary)
                            .background(on ? Brand.accent : Brand.surfaceHigh, in: Capsule())
                            .overlay(Capsule().strokeBorder(Brand.border, lineWidth: on ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Month menu: current year only. Past-year months come from Year → double-tap expand.
    private var periodMenu: some View {
        Menu {
            if grain == .year {
                ForEach(yearOptions) { option in
                    Button {
                        if compareEnabled {
                            toggleCompare(option)
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) { primary = option }
                        }
                    } label: {
                        HStack {
                            Text(option.menuLabel)
                            if option == primary || compared.contains(option) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } else {
                ForEach(currentYearMonths) { option in
                    Button {
                        if compareEnabled {
                            toggleCompare(option)
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) { primary = option }
                        }
                    } label: {
                        HStack {
                            Text(option.menuLabel)
                            if option == primary || compared.contains(option) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(primary.menuLabel)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Brand.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Brand.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func toggleCompare(_ option: FinancePeriod) {
        guard option.grain == grain else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            if option == primary {
                if compared.contains(option) && compared.count > 1 {
                    compared.remove(option)
                } else {
                    compared.insert(option)
                }
                return
            }
            if compared.contains(option) {
                compared.remove(option)
            } else {
                compared.insert(option)
                compared.insert(primary)
            }
        }
    }

    /// Picking a month from an expanded year jumps into month-compare with that month.
    private func selectMonthFromExpandedYear(_ month: FinancePeriod) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            grain = .month
            // Keep any other months already chosen; drop year-level entries
            var next = Set(compared.filter { $0.grain == .month })
            next.insert(month)
            if primary.grain == .month {
                next.insert(primary)
            }
            primary = month
            compared = next
            compareEnabled = true
            expandedYear = nil
        }
    }
}

// MARK: - Billing chart

struct HospitalBillingView: View {
    let profile: HospitalProfile?
    @ObservedObject private var assignments = AssignedShiftsStore.shared
    @ObservedObject private var roster = DoctorRosterStore.shared
    @State private var grain: FinanceGrain = .month
    @State private var primary = FinancePeriod.currentMonth()
    @State private var compareEnabled = false
    @State private var compared: Set<FinancePeriod> = []

    private var hospitalName: String { profile?.name ?? "Average Hospital" }

    private var activePeriods: [FinancePeriod] {
        if compareEnabled {
            var set = compared
            set.insert(primary)
            return set.sorted { $0.id < $1.id }
        }
        return [primary]
    }

    private var series: [FinanceSeriesPoint] {
        if InvestorDemo.usesLocalSampleData {
            if compareEnabled {
                return activePeriods.map { p in
                    FinanceSeriesPoint(
                        id: p.id,
                        period: p,
                        seriesKey: p.shortLabel,
                        value: FinanceMockData.hospitalBilling(period: p, hospitalName: hospitalName)
                    )
                }
            }
            let timeline = FinanceMockData.timeline(for: grain, endingAt: primary, count: grain == .month ? 12 : 5)
            return timeline.map { p in
                FinanceSeriesPoint(
                    id: p.id,
                    period: p,
                    seriesKey: "Committed",
                    value: FinanceMockData.hospitalBilling(period: p, hospitalName: hospitalName)
                )
            }
        }
        if compareEnabled {
            return activePeriods.map { p in
                FinanceSeriesPoint(
                    id: p.id,
                    period: p,
                    seriesKey: p.shortLabel,
                    value: HospitalEarnings.hospitalTotal(hospitalID: profile?.id, period: p)
                )
            }
        }
        let timeline = FinanceMockData.timeline(for: grain, endingAt: primary, count: grain == .month ? 12 : 5)
        return timeline.map { p in
            FinanceSeriesPoint(
                id: p.id,
                period: p,
                seriesKey: "Committed",
                value: HospitalEarnings.hospitalTotal(hospitalID: profile?.id, period: p)
            )
        }
    }

    private var primaryTotal: Double {
        if InvestorDemo.usesLocalSampleData {
            return FinanceMockData.hospitalBilling(period: primary, hospitalName: hospitalName)
        }
        return HospitalEarnings.hospitalTotal(hospitalID: profile?.id, period: primary)
    }

    private var recentLines: [(id: String, title: String, subtitle: String, amount: Double)] {
        if InvestorDemo.usesLocalSampleData {
            let specialties = ["Cardiology", "Emergency Medicine", "Orthopedics", "Internal Medicine", "General Surgery"]
            return (0..<8).map { i in
                let sp = specialties[i % specialties.count]
                let amt = 900.0 + FinanceMockData.unit("line-\(hospitalName)-\(primary.id)-\(i)") * 2_400
                return (
                    id: "\(primary.id)-\(i)",
                    title: "\(sp) coverage",
                    subtitle: primary.shortLabel,
                    amount: amt
                )
            }
        }
        let filled = assignments.assignedShifts.filter {
            $0.shift.hospitalID == profile?.id
                && $0.status != .canceled
                && $0.doctorID != AssignedShiftsStore.coveredBySomeoneElse
                && HospitalEarnings.contains($0.shift.date, primary)
        }.sorted { $0.shift.date > $1.shift.date }
        return filled.prefix(8).map { item in
            let name = roster.doctors.first { $0.id == item.doctorID }?.name ?? "Assigned doctor"
            return (
                id: item.id.uuidString,
                title: "\(item.shift.specialty) coverage",
                subtitle: name,
                amount: HospitalEarnings.committed(item.shift)
            )
        }
    }

    var body: some View {
        ZStack {
            BackgroundGradient()
            ScrollView {
                VStack(spacing: 14) {
                    FinancePeriodChrome(
                        grain: $grain,
                        primary: $primary,
                        compareEnabled: $compareEnabled,
                        compared: $compared
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(compareEnabled ? "Comparison" : "Committed payouts")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Brand.textSecondary)
                                Text(compareEnabled
                                     ? "\(activePeriods.count) \(grain == .year ? "years" : "months")"
                                     : primary.menuLabel)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(Brand.textPrimary)
                            }
                            Spacer()
                            if !compareEnabled {
                                Text(NumberFormat.currency(primaryTotal))
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(Brand.accent)
                                    .contentTransition(.numericText())
                            }
                        }

                        Chart(series) { point in
                            if compareEnabled {
                                BarMark(
                                    x: .value("Period", point.period.shortLabel),
                                    y: .value("Amount", point.value)
                                )
                                .foregroundStyle(by: .value("Series", point.seriesKey))
                                .cornerRadius(6)
                            } else {
                                AreaMark(
                                    x: .value("Period", point.period.shortLabel),
                                    y: .value("Amount", point.value)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Brand.accent.opacity(0.35), Brand.accent.opacity(0.02)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.catmullRom)
                                LineMark(
                                    x: .value("Period", point.period.shortLabel),
                                    y: .value("Amount", point.value)
                                )
                                .foregroundStyle(Brand.accent)
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .interpolationMethod(.catmullRom)
                                PointMark(
                                    x: .value("Period", point.period.shortLabel),
                                    y: .value("Amount", point.value)
                                )
                                .foregroundStyle(Brand.accent)
                                .symbolSize(point.period == primary ? 48 : 20)
                            }
                        }
                        .chartLegend(compareEnabled ? .visible : .hidden)
                        .chartYAxis {
                            AxisMarks(position: .leading) { v in
                                if let d = v.as(Double.self) {
                                    AxisValueLabel {
                                        Text("$\(NumberFormat.grouped(Int((d / 1000).rounded())))k")
                                            .font(.caption2)
                                            .foregroundStyle(Brand.textTertiary)
                                    }
                                }
                                AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                            }
                        }
                        .chartXAxis {
                            AxisMarks { v in
                                AxisValueLabel {
                                    if let s = v.as(String.self) {
                                        Text(s).font(.system(size: 9)).foregroundStyle(Brand.textTertiary)
                                    }
                                }
                            }
                        }
                        .frame(height: 220)
                        .animation(.easeOut(duration: 0.35), value: series.map(\.id))
                    }
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Filled coverage", systemImage: "checkmark.seal.fill")
                        if recentLines.isEmpty {
                            Text("No filled shifts in this period.")
                                .font(.subheadline)
                                .foregroundStyle(Brand.textSecondary)
                        }
                        ForEach(recentLines, id: \.id) { line in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.title).font(.subheadline.weight(.semibold))
                                    Text(line.subtitle).font(.caption).foregroundStyle(Brand.textSecondary)
                                }
                                Spacer()
                                Text(NumberFormat.currency(line.amount))
                                    .font(.headline)
                                    .foregroundStyle(Brand.accent)
                            }
                            if line.id != recentLines.last?.id { Divider() }
                        }
                    }
                    .cardStyle()
                }
                .padding()
            }
        }
        .navigationTitle("Billing")
        .onChange(of: grain) { _, g in
            primary = g == .year ? .currentYear() : .currentMonth()
        }
    }
}

// MARK: - Analytics doctor "stock" board

struct DoctorStockBoard: View {
    let profile: HospitalProfile?
    @ObservedObject private var roster = DoctorRosterStore.shared
    @State private var grain: FinanceGrain = .month
    @State private var primary = FinancePeriod.currentMonth()
    @State private var compareEnabled = false
    @State private var compared: Set<FinancePeriod> = []

    private var specialties: [String] {
        if InvestorDemo.usesLocalSampleData {
            return [
                "Anesthesiology", "Cardiology", "Emergency Medicine", "General Surgery",
                "Internal Medicine", "Neurology", "Orthopedics", "Pediatrics",
            ]
        }
        return Array(Set(roster.doctors.map(\.specialty))).sorted()
    }

    var body: some View {
        VStack(spacing: 14) {
            FinancePeriodChrome(
                grain: $grain,
                primary: $primary,
                compareEnabled: $compareEnabled,
                compared: $compared
            )

            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: "Doctor index by specialty", systemImage: "chart.line.uptrend.xyaxis")
                    .padding(.bottom, 12)

                ForEach(Array(specialties.enumerated()), id: \.element) { i, specialty in
                    if i > 0 { SubtleDivider().padding(.vertical, 8) }
                    NavigationLink {
                        SpecialtyDoctorStockList(
                            specialty: specialty,
                            hospitalID: profile?.id,
                            grain: grain,
                            primary: primary,
                            compareEnabled: compareEnabled,
                            compared: compared
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "stethoscope")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Brand.accent)
                                .frame(width: 30, height: 30)
                                .background(Brand.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(specialty)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Brand.textPrimary)
                                Text("\(doctorCount(specialty)) doctors")
                                    .font(.caption)
                                    .foregroundStyle(Brand.textTertiary)
                            }
                            Spacer()
                            let spark = sparkValues(for: specialty)
                            let showSpark = InvestorDemo.usesLocalSampleData || spark.contains { $0 > 0 }
                            if showSpark {
                                MiniSparkline(values: spark)
                                    .frame(width: 72, height: 28)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Brand.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .cardStyle()
        }
        .onAppear {
            DoctorRosterStore.shared.seedMockDoctorsIfNeeded()
        }
    }

    private func doctorCount(_ specialty: String) -> Int {
        if InvestorDemo.usesLocalSampleData { return mockDoctors(for: specialty).count }
        return roster.doctors.filter { $0.specialty == specialty }.count
    }

    private func sparkValues(for specialty: String) -> [Double] {
        let timeline = FinanceMockData.timeline(for: grain, endingAt: primary, count: 8)
        if InvestorDemo.usesLocalSampleData {
            let names = doctors(for: specialty).map(\.name)
            return timeline.map { FinanceMockData.specialtyIndex(period: $0, specialty: specialty, doctorNames: names) }
        }
        let ids = doctors(for: specialty).map(\.id)
        return timeline.map {
            HospitalEarnings.specialtyTotal(hospitalID: profile?.id, specialty: specialty, doctorIDs: ids, period: $0)
        }
    }

    private func doctors(for specialty: String) -> [DoctorSummary] {
        if InvestorDemo.usesLocalSampleData { return mockDoctors(for: specialty) }
        return roster.doctors.filter { $0.specialty == specialty }
    }
}

private func mockDoctors(for specialty: String) -> [DoctorSummary] {
    let names: [String: [String]] = [
        "Anesthesiology": ["Dr. Priya Nair", "Dr. Marcus Holt", "Dr. Elena Vargas"],
        "Cardiology": ["Dr. James Carter", "Dr. Lisa Chen", "Dr. Ava Brooks", "Dr. Henry Okonkwo"],
        "Emergency Medicine": ["Dr. Maria Santos", "Dr. Emily Walsh", "Dr. Noah Reed", "Dr. Claire Dunn"],
        "General Surgery": ["Dr. Sarah Kim", "Dr. Owen Blake", "Dr. Tara Singh"],
        "Internal Medicine": ["Dr. Robert Nguyen", "Dr. Mia Cole", "Dr. Ethan Ruiz", "Dr. Sofia Alvarez"],
        "Neurology": ["Dr. Benjamin Cross", "Dr. Hannah Yi", "Dr. Lucas Freitag"],
        "Orthopedics": ["Dr. David Park", "Dr. Grace Liu", "Dr. Ian Moreau"],
        "Pediatrics": ["Dr. Amira Hassan", "Dr. Kyle Brennan", "Dr. Nina Patel"],
    ]
    let list = names[specialty] ?? ["Dr. Alex Morgan", "Dr. Jordan Lee", "Dr. Riley Quinn"]
    return list.enumerated().map { i, name in
        let hex = String(format: "%08X", abs(specialty.hashValue) & 0xFFFFFFFF)
        let id = UUID(uuidString: "B\(hex.prefix(7))-\(String(format: "%04d", i + 1))-4000-8000-0000000000\(String(format: "%02d", i + 1))")
            ?? UUID()
        return DoctorSummary(
            id: id,
            name: name,
            credential: i % 2 == 0 ? "MD" : "DO",
            specialty: specialty,
            npi: String(format: "%010d", 1_000_000_000 + abs(name.hashValue % 899_999_999)),
            isAutoApproved: true,
            verificationStatus: .verified
        )
    }
}

struct SpecialtyDoctorStockList: View {
    let specialty: String
    let hospitalID: UUID?
    @State private var grain: FinanceGrain
    @State private var primary: FinancePeriod
    @State private var compareEnabled: Bool
    @State private var compared: Set<FinancePeriod>

    @ObservedObject private var roster = DoctorRosterStore.shared
    @ObservedObject private var assignments = AssignedShiftsStore.shared

    init(
        specialty: String,
        hospitalID: UUID?,
        grain: FinanceGrain,
        primary: FinancePeriod,
        compareEnabled: Bool,
        compared: Set<FinancePeriod>
    ) {
        self.specialty = specialty
        self.hospitalID = hospitalID
        _grain = State(initialValue: grain)
        _primary = State(initialValue: primary)
        _compareEnabled = State(initialValue: compareEnabled)
        _compared = State(initialValue: compared)
    }

    private var doctors: [DoctorSummary] {
        if InvestorDemo.usesLocalSampleData {
            return mockDoctors(for: specialty).sorted { $0.name < $1.name }
        }
        return roster.doctors.filter { $0.specialty == specialty }.sorted { $0.name < $1.name }
    }

    private var doctorNames: [String] { doctors.map(\.name) }

    private var activePeriods: [FinancePeriod] {
        if compareEnabled {
            var set = compared
            set.insert(primary)
            return set.sorted { $0.id < $1.id }
        }
        return [primary]
    }

    private func specialtyValue(_ period: FinancePeriod) -> Double {
        _ = assignments.assignedShifts
        if InvestorDemo.usesLocalSampleData {
            return FinanceMockData.specialtyIndex(period: period, specialty: specialty, doctorNames: doctorNames)
        }
        return HospitalEarnings.specialtyTotal(
            hospitalID: hospitalID,
            specialty: specialty,
            doctorIDs: doctors.map(\.id),
            period: period
        )
    }

    private var series: [FinanceSeriesPoint] {
        if compareEnabled {
            return activePeriods.map { p in
                FinanceSeriesPoint(
                    id: p.id,
                    period: p,
                    seriesKey: p.shortLabel,
                    value: specialtyValue(p)
                )
            }
        }
        let timeline = FinanceMockData.timeline(for: grain, endingAt: primary, count: grain == .month ? 18 : 6)
        return timeline.map { p in
            FinanceSeriesPoint(
                id: p.id,
                period: p,
                seriesKey: specialty,
                value: specialtyValue(p)
            )
        }
    }

    private var last: Double { specialtyValue(primary) }

    private var change: Double {
        let timeline = FinanceMockData.timeline(for: grain, endingAt: primary, count: 2)
        guard timeline.count == 2 else { return 0 }
        return specialtyValue(timeline[1]) - specialtyValue(timeline[0])
    }

    var body: some View {
        ZStack {
            BackgroundGradient()
            ScrollView {
                VStack(spacing: 14) {
                    FinancePeriodChrome(
                        grain: $grain,
                        primary: $primary,
                        compareEnabled: $compareEnabled,
                        compared: $compared
                    )

                    EarningsIndexChartCard(
                        title: specialty,
                        subtitle: InvestorDemo.usesLocalSampleData
                            ? "Specialty average · \(doctors.count) doctors"
                            : "Committed pay · \(doctors.count) doctors",
                        last: last,
                        change: change,
                        series: series,
                        compareEnabled: compareEnabled,
                        showsCurrency: !InvestorDemo.usesLocalSampleData
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Doctors", systemImage: "person.3.fill")
                        ForEach(doctors) { doc in
                            NavigationLink {
                                DoctorStockChartView(
                                    doctor: doc,
                                    hospitalID: hospitalID,
                                    grain: grain,
                                    primary: primary,
                                    compareEnabled: compareEnabled,
                                    compared: compared
                                )
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(Brand.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(doc.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Brand.textPrimary)
                                        Text("\(doc.credential) · \(specialty)")
                                            .font(.caption)
                                            .foregroundStyle(Brand.textSecondary)
                                    }
                                    Spacer()
                                    let docLast = InvestorDemo.usesLocalSampleData
                                        ? FinanceMockData.doctorIndex(period: primary, doctorName: doc.name, specialty: specialty)
                                        : HospitalEarnings.doctorTotal(hospitalID: hospitalID, doctorID: doc.id, period: primary)
                                    Text(InvestorDemo.usesLocalSampleData ? NumberFormat.grouped(docLast) : NumberFormat.currency(docLast))
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(Brand.success)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Brand.textTertiary)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            if doc.id != doctors.last?.id {
                                SubtleDivider()
                            }
                        }
                    }
                    .cardStyle()
                }
                .padding()
            }
        }
        .navigationTitle(specialty)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DoctorStockChartView: View {
    let doctor: DoctorSummary
    let hospitalID: UUID?
    @ObservedObject private var assignments = AssignedShiftsStore.shared
    @State var grain: FinanceGrain
    @State var primary: FinancePeriod
    @State var compareEnabled: Bool
    @State var compared: Set<FinancePeriod>

    private func doctorValue(_ period: FinancePeriod) -> Double {
        _ = assignments.assignedShifts
        if InvestorDemo.usesLocalSampleData {
            return FinanceMockData.doctorIndex(period: period, doctorName: doctor.name, specialty: doctor.specialty)
        }
        return HospitalEarnings.doctorTotal(hospitalID: hospitalID, doctorID: doctor.id, period: period)
    }

    private var activePeriods: [FinancePeriod] {
        if compareEnabled {
            var set = compared
            set.insert(primary)
            return set.sorted { $0.id < $1.id }
        }
        return [primary]
    }

    private var series: [FinanceSeriesPoint] {
        if compareEnabled {
            return activePeriods.map { p in
                FinanceSeriesPoint(
                    id: p.id,
                    period: p,
                    seriesKey: p.shortLabel,
                    value: doctorValue(p)
                )
            }
        }
        let timeline = FinanceMockData.timeline(for: grain, endingAt: primary, count: grain == .month ? 18 : 6)
        return timeline.map { p in
            FinanceSeriesPoint(
                id: p.id,
                period: p,
                seriesKey: doctor.name,
                value: doctorValue(p)
            )
        }
    }

    private var last: Double { doctorValue(primary) }

    private var change: Double {
        let timeline = FinanceMockData.timeline(for: grain, endingAt: primary, count: 2)
        guard timeline.count == 2 else { return 0 }
        return doctorValue(timeline[1]) - doctorValue(timeline[0])
    }

    var body: some View {
        ZStack {
            BackgroundGradient()
            ScrollView {
                VStack(spacing: 14) {
                    FinancePeriodChrome(
                        grain: $grain,
                        primary: $primary,
                        compareEnabled: $compareEnabled,
                        compared: $compared
                    )

                    EarningsIndexChartCard(
                        title: doctor.name,
                        subtitle: InvestorDemo.usesLocalSampleData
                            ? "\(doctor.specialty) · earnings index"
                            : "\(doctor.specialty) · committed pay",
                        last: last,
                        change: change,
                        series: series,
                        compareEnabled: compareEnabled,
                        showsCurrency: !InvestorDemo.usesLocalSampleData
                    )
                }
                .padding()
            }
        }
        .navigationTitle("Index")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Shared stock-style earnings index chart (specialty average or single doctor).
private struct EarningsIndexChartCard: View {
    let title: String
    let subtitle: String
    let last: Double
    let change: Double
    let series: [FinanceSeriesPoint]
    let compareEnabled: Bool
    var showsCurrency: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.bold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Brand.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(showsCurrency ? NumberFormat.currency(last) : NumberFormat.grouped(last))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.textPrimary)
                Text("\(change >= 0 ? "+" : "")\(showsCurrency ? NumberFormat.currency(change) : NumberFormat.grouped(change))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(change >= 0 ? Brand.success : Brand.danger)
            }

            Chart(series) { point in
                if compareEnabled {
                    LineMark(
                        x: .value("Period", point.period.shortLabel),
                        y: .value("Index", point.value)
                    )
                    .foregroundStyle(by: .value("Series", point.seriesKey))
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                } else {
                    AreaMark(
                        x: .value("Period", point.period.shortLabel),
                        y: .value("Index", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                (change >= 0 ? Brand.success : Brand.danger).opacity(0.28),
                                (change >= 0 ? Brand.success : Brand.danger).opacity(0.02),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("Period", point.period.shortLabel),
                        y: .value("Index", point.value)
                    )
                    .foregroundStyle(change >= 0 ? Brand.success : Brand.danger)
                    .lineStyle(StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartLegend(compareEnabled ? .visible : .hidden)
            .frame(height: 240)
            .animation(.easeOut(duration: 0.35), value: series.map(\.id))
        }
        .cardStyle()
    }
}

private struct MiniSparkline: View {
    let values: [Double]

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { item in
            LineMark(
                x: .value("i", item.offset),
                y: .value("v", item.element)
            )
            .foregroundStyle(Brand.success)
            .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}
