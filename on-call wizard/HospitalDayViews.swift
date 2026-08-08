import SwiftUI

// MARK: - Hover preview (pointer / long-press)

struct HospitalDayHoverCard: View {
    let summary: HospitalDaySummary

    private var level: CalendarHeatmap.DayData.CoverageFillLevel { summary.coverageFillLevel }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(summary.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                coverageBadge(level)
                if summary.isBlocked {
                    Label("Blocked", systemImage: "xmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.danger)
                }
            }

            if summary.isBlocked {
                Text("Day is blocked — toggle in detail view to reopen.")
                    .font(.caption)
                    .foregroundStyle(Brand.textSecondary)
            }

            columnHeaders

            Divider().opacity(0.35)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    specialtyList
                }
            }
            .frame(maxHeight: 260)

            if summary.totalPaid > 0, level == .allFilled {
                Divider().opacity(0.35)
                HStack {
                    Text("Day total")
                        .font(.caption)
                        .foregroundStyle(Brand.textSecondary)
                    Spacer()
                    Text(NumberFormat.currency(summary.totalPaid))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Brand.accent)
                }
            }

            Text("Long press for details · Tap specialty to edit doctor pay")
                .font(.caption2)
                .foregroundStyle(Brand.textTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Brand.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    @ViewBuilder
    private var columnHeaders: some View {
        HStack(spacing: 8) {
            Text("Specialty")
                .frame(maxWidth: .infinity, alignment: .leading)
            if level == .allFilled {
                Text("On call")
                    .frame(width: 96, alignment: .leading)
            }
            Text(rateColumnTitle)
                .frame(width: 72, alignment: .trailing)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Brand.textTertiary)
    }

    private var rateColumnTitle: String {
        switch level {
        case .allFilled: return "Approved"
        case .noneFilled: return "Going rate"
        case .partial: return "Rate"
        }
    }

    @ViewBuilder
    private var specialtyList: some View {
        switch level {
        case .partial:
            partialSpecialtyList
        case .allFilled, .noneFilled:
            defaultSpecialtyList
        }
    }

    @ViewBuilder
    private var partialSpecialtyList: some View {
        let unfilled = summary.hoverUnfilledRows
        let filled = summary.hoverFilledRows
        let unposted = summary.hoverUnpostedRows

        if !unfilled.isEmpty {
            sectionLabel("Needs coverage")
            ForEach(unfilled) { row in
                specialtyLine(row)
                trailingDivider(for: row, in: unfilled)
            }
        }
        if !filled.isEmpty {
            sectionLabel("Filled")
            ForEach(filled) { row in
                specialtyLine(row)
                trailingDivider(for: row, in: filled)
            }
        }
        ForEach(unposted) { row in
            specialtyLine(row)
            trailingDivider(for: row, in: unposted)
        }
    }

    @ViewBuilder
    private var defaultSpecialtyList: some View {
        let rows = summary.hoverOrderedRows
        ForEach(rows) { row in
            specialtyLine(row)
            trailingDivider(for: row, in: rows)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Brand.textTertiary)
            .padding(.top, 6)
            .padding(.bottom, 4)
    }

    private func trailingDivider(for row: HospitalDaySummary.SpecialtyRow, in allRows: [HospitalDaySummary.SpecialtyRow]) -> some View {
        Group {
            if row.id != allRows.last?.id {
                Divider().opacity(0.2)
            }
        }
    }

    private func specialtyLine(_ row: HospitalDaySummary.SpecialtyRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor(for: row))
                    .frame(width: 7, height: 7)
                Text(row.specialty)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if level == .allFilled {
                Group {
                    if let name = row.onCallDoctorName {
                        Text("\(name)\(row.onCallCredential.map { ", \($0)" } ?? "")")
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text("—")
                            .foregroundStyle(Brand.textTertiary)
                    }
                }
                .font(.caption)
                .frame(width: 96, alignment: .leading)
            }

            Text(rateText(for: row))
                .font(.caption.weight(.semibold))
                .foregroundStyle(rateColor(for: row))
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private func rateText(for row: HospitalDaySummary.SpecialtyRow) -> String {
        switch level {
        case .allFilled:
            if let rate = row.approvedRate {
                return "\(NumberFormat.currency(rate))\(row.rateUnitLabel)"
            }
            return row.hasShiftPosted ? "—" : proposedRateLabel(for: row)
        case .noneFilled:
            if let rate = row.goingRate {
                return "\(NumberFormat.currency(rate))\(row.rateUnitLabel)"
            }
            return proposedRateLabel(for: row)
        case .partial:
            if row.isFilled, let rate = row.approvedRate {
                return "\(NumberFormat.currency(rate))\(row.rateUnitLabel)"
            }
            if row.hasShiftPosted, let rate = row.goingRate {
                return "\(NumberFormat.currency(rate))\(row.rateUnitLabel)"
            }
            return proposedRateLabel(for: row)
        }
    }

    private func proposedRateLabel(for row: HospitalDaySummary.SpecialtyRow) -> String {
        if let rate = row.proposedRate {
            return "\(NumberFormat.currency(rate))\(row.rateUnitLabel)"
        }
        return "No shift"
    }

    private func rateColor(for row: HospitalDaySummary.SpecialtyRow) -> Color {
        if !row.hasShiftPosted { return Brand.textTertiary }
        if row.isFilled { return Brand.textPrimary }
        return Brand.warning
    }

    private func statusColor(for row: HospitalDaySummary.SpecialtyRow) -> Color {
        if row.isFilled { return Color(hex: "22C55E") }
        if row.hasShiftPosted { return Color(hex: "EF4444") }
        return Color.white.opacity(0.25)
    }

    @ViewBuilder
    private func coverageBadge(_ level: CalendarHeatmap.DayData.CoverageFillLevel) -> some View {
        let (label, color): (String, Color) = switch level {
        case .allFilled: ("All filled", Color(hex: "22C55E"))
        case .partial: ("Partial", Color(hex: "EAB308"))
        case .noneFilled: ("Unfilled", Color(hex: "EF4444"))
        }
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Detail sheet (tap)

struct HospitalDayDetailSheet: View {
    let date: Date
    let hospitalID: UUID

    @Environment(\.dismiss) private var dismiss
    @StateObject private var tokens = TokenStore.shared
    @StateObject private var unavailable = UnavailableDaysStore.shared
    @StateObject private var proposedRates = ProposedRateStore.shared
    @State private var rateEditor: ProposedRateEditorContext?

    private var summary: HospitalDaySummary {
        HospitalDayInsights.summary(for: date, hospitalID: hospitalID)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundGradient()
                ScrollView {
                    VStack(spacing: 14) {
                        headerCard

                        ForEach(summary.specialtyRows) { row in
                            specialtyCard(row)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(summary.date.formatted(.dateTime.month(.wide).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $rateEditor) { context in
                ProposedRateEditorSheet(context: context)
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                        .font(.headline)
                    Text("\(summary.approvedRequestCount) approved · \(summary.pendingRequestCount) pending requests")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if summary.totalPaid > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(NumberFormat.currency(summary.totalPaid))
                            .font(.title2.bold())
                            .foregroundStyle(Brand.accent)
                        Text("total paid")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Toggle(isOn: Binding(
                get: { unavailable.isBlocked(date, hospitalID: hospitalID) },
                set: { _ in unavailable.toggle(date, hospitalID: hospitalID) }
            )) {
                Label("Block this day", systemImage: "xmark.circle")
                    .font(.subheadline.weight(.medium))
            }
            .tint(Brand.danger)
        }
        .cardStyle()
    }

    private func proposedRateRow(_ row: HospitalDaySummary.SpecialtyRow, rate: Double) -> some View {
        Button {
            rateEditor = ProposedRateEditorContext(
                specialty: row.specialty,
                date: date,
                hospitalID: hospitalID
            )
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Proposed rate (algorithm)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(Brand.accent.opacity(0.8))
                    }
                    if row.isProposedRateCustom {
                        Text("Custom override · tap to edit")
                            .font(.caption2)
                            .foregroundStyle(Brand.textTertiary)
                    } else {
                        Text("Tap to adjust before posting")
                            .font(.caption2)
                            .foregroundStyle(Brand.textTertiary)
                    }
                }
                Spacer()
                Text("\(NumberFormat.currency(rate))\(row.rateUnitLabel)")
                    .font(.headline)
                    .foregroundStyle(Brand.accent)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func specialtyCard(_ row: HospitalDaySummary.SpecialtyRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                SpecialtyDayDoctorsView(
                    date: date,
                    hospitalID: hospitalID,
                    specialty: row.specialty,
                    rateUnitLabel: row.rateUnitLabel
                )
            } label: {
                HStack {
                    Text(row.specialty)
                        .font(.headline)
                        .foregroundStyle(Brand.textPrimary)
                    Spacer()
                    if !row.hasShiftPosted {
                        Label("No shift", systemImage: "minus.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.textTertiary)
                    } else if row.isFilled {
                        Label("Filled", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.success)
                    } else {
                        Label("Open", systemImage: "clock")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.warning)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.textTertiary)
                }
            }
            .buttonStyle(.plain)

            // Always-editable specialty rate for this day
            SpecialtyDayRateRow(
                specialty: row.specialty,
                date: date,
                hospitalID: hospitalID,
                displayRate: row.approvedRate ?? row.goingRate ?? row.proposedRate ?? 1200,
                unitLabel: row.rateUnitLabel,
                hasOpenShift: row.hasShiftPosted && !row.isFilled,
                existingShift: row.shift
            )

            if let name = row.onCallDoctorName {
                HStack {
                    Image(systemName: "stethoscope")
                        .foregroundStyle(Brand.accent)
                    Text("\(name)\(row.onCallCredential.map { ", \($0)" } ?? "")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.textPrimary)
                    Spacer()
                    if let rate = row.approvedRate {
                        Text("\(NumberFormat.currency(rate))\(row.rateUnitLabel)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Brand.accent)
                    }
                }
            }

            if !row.tokenRequests.isEmpty {
                Divider()
                Text("Coverage requests")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                ForEach(row.tokenRequests) { req in
                    tokenRequestRow(req)
                    if req.id != row.tokenRequests.last?.id { Divider() }
                }
            } else {
                Text("Tap specialty name to set individual doctor pay")
                    .font(.caption2)
                    .foregroundStyle(Brand.textTertiary)
            }
        }
        .cardStyle()
    }

    private func tokenRequestRow(_ req: HospitalDaySummary.TokenSummary) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(req.doctorName), \(req.credential)")
                    .font(.subheadline.weight(.medium))
                VStack(alignment: .leading, spacing: 2) {
                    Label("Requested \(req.requestedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar.badge.plus")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let approved = req.approvedAt, req.status == .approved || req.status == .autoApproved {
                        Label("Approved \(approved.formatted(date: .abbreviated, time: .shortened))", systemImage: "checkmark.circle")
                            .font(.caption2)
                            .foregroundStyle(Brand.success)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                tokenStatusBadge(req.status)
                if req.status == .pending {
                    HStack(spacing: 6) {
                        Button {
                            tokens.approve(id: req.id)
                            NotificationService.shared.notifyTokenDecision(approved: true, date: summary.date)
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Brand.success)
                        }
                        .buttonStyle(.plain)
                        Button {
                            tokens.deny(id: req.id)
                            NotificationService.shared.notifyTokenDecision(approved: false, date: summary.date)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Brand.danger)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tokenStatusBadge(_ status: TokenStore.TokenRequest.RequestStatus) -> some View {
        let (label, color): (String, Color) = switch status {
        case .pending: ("Pending", Brand.warning)
        case .approved: ("Approved", Brand.success)
        case .autoApproved: ("Auto", Brand.accent)
        case .denied: ("Denied", Brand.danger)
        }
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Proposed rate editor

struct ProposedRateEditorContext: Identifiable {
    let specialty: String
    let date: Date
    let hospitalID: UUID

    var id: String { "\(specialty)-\(date.onlyDate().timeIntervalSince1970)" }
}

struct ProposedRateEditorSheet: View {
    let context: ProposedRateEditorContext

    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = ProposedRateStore.shared
    @StateObject private var policyStore = SchedulingPolicyStore.shared
    @State private var rate: Double = 0
    @State private var algorithmRate: Double = 0
    @State private var isCustom = false

    private var isHourly: Bool {
        policyStore.policy(for: context.hospitalID).granularity == .hour
    }

    private var unitLabel: String { isHourly ? "/hr" : "/day" }
    private var step: Double { isHourly ? 5 : 50 }
    private var validRange: ClosedRange<Double> { isHourly ? 80...600 : 800...8_000 }

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundGradient()
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.specialty)
                            .font(.title2.bold())
                        Text(context.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Proposed rate")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(NumberFormat.currency(rate))\(unitLabel)")
                                .font(.title.bold())
                                .foregroundStyle(Brand.accent)
                        }
                        Stepper("Adjust rate", value: $rate, in: validRange, step: step)
                            .labelsHidden()
                            .onChange(of: rate) { _, newValue in
                                isCustom = abs(newValue - algorithmRate) >= step / 2
                            }
                    }
                    .cardStyle()

                    Label {
                        Text("Algorithm suggests \(NumberFormat.currency(algorithmRate))\(unitLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Brand.accent)
                    }

                    if isCustom {
                        Button {
                            store.resetToAlgorithm(
                                specialty: context.specialty,
                                date: context.date,
                                hospitalID: context.hospitalID
                            )
                            algorithmRate = store.algorithmRate(
                                specialty: context.specialty,
                                date: context.date,
                                hospitalID: context.hospitalID
                            )
                            rate = algorithmRate
                            isCustom = false
                        } label: {
                            Label("Reset to algorithm", systemImage: "arrow.counterclockwise")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(Brand.accent)
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Edit Rate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if isCustom || abs(rate - algorithmRate) >= step / 2 {
                            store.setRate(
                                rate,
                                specialty: context.specialty,
                                date: context.date,
                                hospitalID: context.hospitalID
                            )
                        } else {
                            store.resetToAlgorithm(
                                specialty: context.specialty,
                                date: context.date,
                                hospitalID: context.hospitalID
                            )
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { loadRates() }
        }
        .presentationDetents([.medium])
    }

    private func loadRates() {
        let proposal = store.proposedRate(
            specialty: context.specialty,
            date: context.date,
            hospitalID: context.hospitalID
        )
        rate = proposal.rate
        algorithmRate = proposal.algorithmRate
        isCustom = proposal.isCustom
    }
}

// MARK: - Always-editable specialty day rate

struct SpecialtyDayRateRow: View {
    let specialty: String
    let date: Date
    let hospitalID: UUID
    let displayRate: Double
    let unitLabel: String
    let hasOpenShift: Bool
    let existingShift: Shift?

    @ObservedObject private var proposed = ProposedRateStore.shared
    @State private var rate: Double = 1200

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Rate for this day")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(NumberFormat.currency(rate))\(unitLabel)")
                    .font(.headline)
                    .foregroundStyle(Brand.accent)
            }
            Slider(value: $rate, in: 100...5000, step: 25) { editing in
                if !editing { commit() }
            }
            .tint(Brand.accent)
        }
        .onAppear {
            let proposal = proposed.proposedRate(specialty: specialty, date: date, hospitalID: hospitalID)
            rate = proposal.isCustom ? proposal.rate : displayRate
        }
    }

    private func commit() {
        proposed.setRate(rate, specialty: specialty, date: date, hospitalID: hospitalID)
        if let shift = existingShift, hasOpenShift {
            let updated = Shift(
                id: shift.id,
                hospitalID: shift.hospitalID,
                hospital: shift.hospital,
                specialty: shift.specialty,
                start: shift.start,
                durationHours: shift.durationHours,
                rateFloor: rate,
                rateUnit: shift.rateUnit,
                escalationMode: .flat(rate),
                escalationIntervalHours: shift.escalationIntervalHours,
                usesAlgorithmPricing: false
            )
            Services.hospital.upsertShift(updated)
        }
    }
}

// MARK: - Specialty → doctors pay for a single day

struct SpecialtyDayDoctorsView: View {
    let date: Date
    let hospitalID: UUID
    let specialty: String
    let rateUnitLabel: String

    @ObservedObject private var roster = DoctorRosterStore.shared
    @ObservedObject private var proposed = ProposedRateStore.shared
    @ObservedObject private var policyStore = SchedulingPolicyStore.shared

    private var doctors: [DoctorSummary] {
        let real = roster.doctors.filter { $0.specialty == specialty }
        if !real.isEmpty { return real }
        // Fallback demo doctors for empty specialties
        return [
            DoctorSummary(name: "Dr. Alex Rivera", credential: "MD", specialty: specialty, npi: "1000000001", isAutoApproved: true),
            DoctorSummary(name: "Dr. Jordan Lee", credential: "DO", specialty: specialty, npi: "1000000002", isAutoApproved: false),
            DoctorSummary(name: "Dr. Sam Patel", credential: "MD", specialty: specialty, npi: "1000000003", isAutoApproved: true),
        ]
    }

    private func fallbackRate(for doc: DoctorSummary) -> Double {
        policyStore.policy.doctorBaseRates[doc.id.uuidString]
            ?? policyStore.policy.specialtyBaseRates[specialty]
            ?? 1200
    }

    var body: some View {
        ZStack {
            BackgroundGradient()
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: specialty, systemImage: "stethoscope")
                        Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Adjust pay for each doctor on this day only. Global rates live under Doctors.")
                            .font(.caption)
                            .foregroundStyle(Brand.textSecondary)
                    }
                    .cardStyle()

                    ForEach(doctors) { doc in
                        DoctorDayPayRow(
                            doctor: doc,
                            date: date,
                            hospitalID: hospitalID,
                            unitLabel: rateUnitLabel,
                            fallback: fallbackRate(for: doc)
                        )
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Doctor Pay")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DoctorDayPayRow: View {
    let doctor: DoctorSummary
    let date: Date
    let hospitalID: UUID
    let unitLabel: String
    let fallback: Double

    @ObservedObject private var proposed = ProposedRateStore.shared
    @State private var rate: Double = 1200

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(doctor.name), \(doctor.credential)")
                        .font(.subheadline.weight(.semibold))
                    Text(doctor.npi.isEmpty ? doctor.specialty : "NPI \(doctor.npi)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(NumberFormat.currency(rate))\(unitLabel)")
                    .font(.headline)
                    .foregroundStyle(Brand.accent)
            }
            Slider(value: $rate, in: 100...5000, step: 25) { editing in
                if !editing {
                    proposed.setDoctorDayRate(rate, doctorID: doctor.id, date: date, hospitalID: hospitalID)
                }
            }
            .tint(Brand.accent)
        }
        .cardStyle()
        .onAppear {
            rate = proposed.doctorDayRate(doctorID: doctor.id, date: date, hospitalID: hospitalID, fallback: fallback)
        }
    }
}
