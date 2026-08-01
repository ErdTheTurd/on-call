import SwiftUI

// MARK: - Hospital On Call Settings

struct HospitalPolicySettingsView: View {
    let hospitalProfile: HospitalProfile?
    @StateObject private var policyStore = SchedulingPolicyStore.shared
    @State private var didSave = false
    @State private var selectedTab: OnCallSettingsTab = .general

    private enum OnCallSettingsTab: String, CaseIterable {
        case general = "General"
        case cancellation = "Cancellation"
        case payRates = "Pay Rates"
    }

    var body: some View {
        ZStack {
            BackgroundGradient()
            ScrollView {
                VStack(spacing: 16) {
                    // Custom pill tab switcher
                    HStack(spacing: 4) {
                        ForEach(OnCallSettingsTab.allCases, id: \.self) { tab in
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                    selectedTab = tab
                                }
                            } label: {
                                Text(tab.rawValue)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(selectedTab == tab ? .white : Brand.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background {
                                        if selectedTab == tab {
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

                    switch selectedTab {
                    case .general:      generalSettings
                    case .cancellation: cancellationSettings
                    case .payRates:     payRatesSettings
                    }

                    // Save button
                    Button {
                        policyStore.saveForHospital(hospitalProfile)
                        withAnimation(.spring(response: 0.3)) { didSave = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation { didSave = false }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if didSave {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Saved!")
                            } else {
                                Text("Save Settings")
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("On Call")
        .onAppear { policyStore.loadForHospital(hospitalProfile) }
    }

    // MARK: General tab

    private var generalSettings: some View {
        VStack(spacing: 12) {
            // Approval Mode
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Approval Mode", systemImage: "person.badge.shield.checkmark.fill")
                PolicyToggleRow(
                    title: "Administrator approve shifts",
                    subtitle: policyStore.policy.administratorApproveShifts
                        ? "Doctors must be manually approved by staff"
                        : "Verified doctors are auto-approved by the algorithm",
                    isOn: $policyStore.policy.administratorApproveShifts
                )
            }
            .cardStyle()

            // Scheduling Unit
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Scheduling Unit", systemImage: "calendar")
                Text("Per day is standard. Switch to hourly only if your facility tracks specific start and end times.")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("Unit", selection: $policyStore.policy.granularity) {
                    Text("Per Day").tag(SchedulingPolicy.Granularity.day)
                    Text("Per Hour").tag(SchedulingPolicy.Granularity.hour)
                }
                .pickerStyle(.segmented)
            }
            .cardStyle()
        }
    }

    // MARK: Cancellation tab

    private var cancellationSettings: some View {
        VStack(spacing: 12) {
            // Base Penalty
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Base Penalty", systemImage: "dollarsign.circle.fill")
                Text("The reference dollar amount for all cancellation fee percentages below.")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.textSecondary)
                PolicySliderRow(
                    label: "Base penalty",
                    value: Binding(
                        get: { Double(truncating: policyStore.policy.basePenaltyAmount as NSNumber) },
                        set: { policyStore.policy.basePenaltyAmount = Decimal($0) }
                    ),
                    range: 50...2000,
                    step: 25,
                    format: { "$\(Int($0))" }
                )
            }
            .cardStyle()

            // Timeframes
            CancellationTimeframesEditor(scale: $policyStore.policy.cancellationPenaltyScale)

            // Cancel cutoff
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Cancel Window", systemImage: "clock.badge.exclamationmark")
                Text("Doctors cannot cancel within this window before a shift starts.")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.textSecondary)
                PolicySliderRow(
                    label: "Cutoff",
                    value: Binding(
                        get: { Double(policyStore.policy.cancelWindowHours) },
                        set: { policyStore.policy.cancelWindowHours = Int($0) }
                    ),
                    range: 0...Double(PolicyLeadTimeFormatter.maxPolicyHours),
                    step: 1,
                    format: { PolicyLeadTimeFormatter.beforeStartLabel(hours: Int($0)) }
                )
            }
            .cardStyle()

            TradePenaltyEditor(policy: $policyStore.policy)
        }
    }

    // MARK: Pay Rates tab

    private var payRatesSettings: some View {
        SpecialtyPayEditor(policy: $policyStore.policy)
    }
}

// MARK: - Specialty pay editor

private struct SpecialtyPayEditor: View {
    @Binding var policy: SchedulingPolicy
    @ObservedObject private var roster = DoctorRosterStore.shared
    @State private var expandedSpecialty: String? = nil

    private static let defaultRate: Double = 500

    // MARK: Mock data (used when no real doctors are registered)

    private static let mockSpecialtyRates: [String: Double] = [
        "Cardiology":         850,
        "Emergency Medicine": 750,
        "Orthopedics":        700,
        "General Surgery":    625,
        "Internal Medicine":  500
    ]

    private static let mockDoctors: [DoctorSummary] = [
        .init(id: UUID(uuidString: "A0000001-0000-0000-0000-000000000001")!, name: "Dr. Sarah Chen",      credential: "MD, FACC",  specialty: "Cardiology",         isAutoApproved: true,  verificationStatus: .verified),
        .init(id: UUID(uuidString: "A0000001-0000-0000-0000-000000000002")!, name: "Dr. James Wright",    credential: "MD",        specialty: "Cardiology",         isAutoApproved: true,  verificationStatus: .verified),
        .init(id: UUID(uuidString: "A0000001-0000-0000-0000-000000000003")!, name: "Dr. Priya Sharma",    credential: "MD, PhD",   specialty: "Cardiology",         isAutoApproved: false, verificationStatus: .verified),
        .init(id: UUID(uuidString: "A0000002-0000-0000-0000-000000000001")!, name: "Dr. Marcus Johnson",  credential: "MD",        specialty: "Emergency Medicine", isAutoApproved: true,  verificationStatus: .verified),
        .init(id: UUID(uuidString: "A0000002-0000-0000-0000-000000000002")!, name: "Dr. Elena Rodriguez", credential: "DO",        specialty: "Emergency Medicine", isAutoApproved: true,  verificationStatus: .verified),
        .init(id: UUID(uuidString: "A0000003-0000-0000-0000-000000000001")!, name: "Dr. Robert Kim",      credential: "MD, FAAOS", specialty: "Orthopedics",        isAutoApproved: false, verificationStatus: .verified),
        .init(id: UUID(uuidString: "A0000003-0000-0000-0000-000000000002")!, name: "Dr. Amanda Foster",   credential: "MD",        specialty: "Orthopedics",        isAutoApproved: true,  verificationStatus: .verified),
        .init(id: UUID(uuidString: "A0000004-0000-0000-0000-000000000001")!, name: "Dr. Michael Torres",  credential: "MD, FACS",  specialty: "General Surgery",    isAutoApproved: true,  verificationStatus: .verified),
        .init(id: UUID(uuidString: "A0000004-0000-0000-0000-000000000002")!, name: "Dr. Lisa Patel",      credential: "MD",        specialty: "General Surgery",    isAutoApproved: false, verificationStatus: .verified),
        .init(id: UUID(uuidString: "A0000005-0000-0000-0000-000000000001")!, name: "Dr. David Wilson",    credential: "MD",        specialty: "Internal Medicine",  isAutoApproved: true,  verificationStatus: .verified),
        .init(id: UUID(uuidString: "A0000005-0000-0000-0000-000000000002")!, name: "Dr. Jennifer Chang",  credential: "MD, PhD",   specialty: "Internal Medicine",  isAutoApproved: false, verificationStatus: .verified),
        .init(id: UUID(uuidString: "A0000005-0000-0000-0000-000000000003")!, name: "Dr. Omar Hassan",     credential: "DO",        specialty: "Internal Medicine",  isAutoApproved: true,  verificationStatus: .verified),
    ]

    private static let mockDoctorRates: [String: Double] = [
        "A0000001-0000-0000-0000-000000000001": 925,
        "A0000001-0000-0000-0000-000000000002": 850,
        "A0000001-0000-0000-0000-000000000003": 800,
        "A0000002-0000-0000-0000-000000000001": 775,
        "A0000002-0000-0000-0000-000000000002": 725,
        "A0000003-0000-0000-0000-000000000001": 750,
        "A0000003-0000-0000-0000-000000000002": 650,
        "A0000004-0000-0000-0000-000000000001": 700,
        "A0000004-0000-0000-0000-000000000002": 575,
        "A0000005-0000-0000-0000-000000000001": 525,
        "A0000005-0000-0000-0000-000000000002": 550,
        "A0000005-0000-0000-0000-000000000003": 475,
    ]

    // MARK: Derived

    private var useMockData: Bool { roster.doctors.isEmpty }

    private var specialties: [String] {
        useMockData
            ? Array(Self.mockSpecialtyRates.keys).sorted()
            : Array(Set(roster.doctors.map { $0.specialty })).sorted()
    }

    private func doctors(for specialty: String) -> [DoctorSummary] {
        useMockData
            ? Self.mockDoctors.filter { $0.specialty == specialty }
            : roster.doctors.filter { $0.specialty == specialty }
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Base Pay per Shift", systemImage: "dollarsign.circle.fill")
                Text("Set a base pay rate ($100–$5,000) per specialty. Tap a specialty to set individual doctor rates. Moving the specialty slider resets all doctor rates for that specialty.")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .cardStyle()

            ForEach(specialties, id: \.self) { specialty in
                SpecialtyPayRow(
                    specialty: specialty,
                    doctors: doctors(for: specialty),
                    specialtyRate: Binding(
                        get: {
                            policy.specialtyBaseRates[specialty]
                                ?? Self.mockSpecialtyRates[specialty]
                                ?? Self.defaultRate
                        },
                        set: { newRate in
                            policy.specialtyBaseRates[specialty] = newRate
                            for doc in doctors(for: specialty) {
                                policy.doctorBaseRates[doc.id.uuidString] = newRate
                            }
                        }
                    ),
                    doctorRate: { doc in
                        policy.doctorBaseRates[doc.id.uuidString]
                            ?? Self.mockDoctorRates[doc.id.uuidString]
                            ?? policy.specialtyBaseRates[specialty]
                            ?? Self.mockSpecialtyRates[specialty]
                            ?? Self.defaultRate
                    },
                    setDoctorRate: { doc, rate in
                        policy.doctorBaseRates[doc.id.uuidString] = rate
                    },
                    isExpanded: expandedSpecialty == specialty,
                    onToggle: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            expandedSpecialty = expandedSpecialty == specialty ? nil : specialty
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Specialty pay row

private struct SpecialtyPayRow: View {
    let specialty: String
    let doctors: [DoctorSummary]
    @Binding var specialtyRate: Double
    let doctorRate: (DoctorSummary) -> Double
    let setDoctorRate: (DoctorSummary, Double) -> Void
    let isExpanded: Bool
    let onToggle: () -> Void

    @State private var justReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header row ──────────────────────────────────
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(specialty)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Brand.textPrimary)
                        Text(doctors.isEmpty ? "No doctors registered" : "\(doctors.count) doctor\(doctors.count == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundStyle(Brand.textSecondary)
                    }
                    Spacer()
                    ValueChip(text: "$\(Int(specialtyRate))")
                    if !doctors.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Brand.textTertiary)
                            .frame(width: 16)
                    }
                }
            }
            .buttonStyle(.plain)

            // ── Specialty slider ─────────────────────────────
            Slider(value: $specialtyRate, in: 100...5000, step: 25,
                   onEditingChanged: { editing in
                       guard !editing, !doctors.isEmpty else { return }
                       withAnimation(.easeInOut(duration: 0.2)) { justReset = true }
                       DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                           withAnimation { justReset = false }
                       }
                   })
            .tint(Brand.accent)
            .padding(.top, 10)

            // ── Warning / reset badge ────────────────────────
            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.textTertiary)
                Text(doctors.isEmpty
                     ? "Add doctors via the Roster to set individual rates"
                     : "Moving this slider resets all individual doctor rates")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.textTertiary)
                Spacer()
                if justReset {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Doctor rates reset")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Brand.warning)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.top, 6)

            // ── Doctor list (expanded) ───────────────────────
            if isExpanded && !doctors.isEmpty {
                SubtleDivider().padding(.vertical, 12)

                VStack(spacing: 14) {
                    ForEach(doctors, id: \.id) { doctor in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Brand.accentAlt.opacity(0.8))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(doctor.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Brand.textPrimary)
                                    Text(doctor.credential)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Brand.textTertiary)
                                }
                                Spacer()
                                ValueChip(text: "$\(Int(doctorRate(doctor)))")
                            }
                            Slider(
                                value: Binding(
                                    get: { doctorRate(doctor) },
                                    set: { setDoctorRate(doctor, $0) }
                                ),
                                in: 100...5000, step: 25
                            )
                            .tint(Brand.accentAlt)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.07), Color.white.opacity(0.03)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                .strokeBorder(LinearGradient(
                    colors: [Color.white.opacity(0.15), Color.white.opacity(0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isExpanded)
    }
}

// MARK: - Toggle Row

private struct PolicyToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Brand.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Brand.accent)
        }
    }
}

// MARK: - Slider Row

private struct PolicySliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Brand.textPrimary)
                Spacer()
                ValueChip(text: format(value))
            }
            Slider(value: $value, in: range, step: step)
                .tint(Brand.accent)
        }
    }
}

// MARK: - Cancellation Timeframes Editor

private struct CancellationTimeframesEditor: View {
    @Binding var scale: [SchedulingPolicy.PenaltyBracket]
    @State private var showAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeader(title: "Penalty Tiers", systemImage: "xmark.circle.fill")
                Spacer()
                Text("\(scale.count) tier\(scale.count == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Brand.textTertiary)
            }

            Text("Penalty increases as the cancellation happens closer to the shift. Each tier is 100–500% of the base.")
                .font(.system(size: 13))
                .foregroundStyle(Brand.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(scale.indices, id: \.self) { index in
                    let minHours = index > 0 ? scale[index - 1].hoursBeforeStart : 0
                    CancellationTimeframeRow(
                        bracket: bracketBinding(for: index),
                        tierNumber: index + 1,
                        minHours: minHours,
                        canDelete: scale.count > 1,
                        onDelete: { withAnimation(.spring(response: 0.3)) { remove(at: index) } }
                    )
                    if index < scale.count - 1 {
                        SubtleDivider().padding(.vertical, 12)
                    }
                }
            }

            // Add tier button (dashed) — disabled once last tier reaches the 3-month cap
            let atMax = (scale.last?.hoursBeforeStart ?? 0) >= PolicyLeadTimeFormatter.maxPolicyHours
            Button { showAddSheet = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text(atMax ? "Max tiers reached" : "Add Tier")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(atMax ? Brand.textTertiary : Brand.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    (atMax ? Brand.textTertiary : Brand.accent).opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(
                            (atMax ? Brand.textTertiary : Brand.accent).opacity(0.3),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(atMax)
            .padding(.top, 4)
        }
        .cardStyle()
        .sheet(isPresented: $showAddSheet) {
            let min = min(scale.last?.hoursBeforeStart ?? 0, PolicyLeadTimeFormatter.maxPolicyHours - 1)
            AddCancellationTimeframeSheet(scale: $scale, minHours: min)
        }
    }

    private func bracketBinding(for index: Int) -> Binding<SchedulingPolicy.PenaltyBracket> {
        Binding(
            get: { scale[index] },
            set: { newValue in
                scale[index] = newValue
                scale = SchedulingPolicy.normalizeCancellationScale(scale)
            }
        )
    }

    private func remove(at index: Int) {
        guard scale.count > 1 else { return }
        scale.remove(at: index)
        scale = SchedulingPolicy.normalizeCancellationScale(scale)
    }
}

// MARK: - Timeframe Row

private struct CancellationTimeframeRow: View {
    @Binding var bracket: SchedulingPolicy.PenaltyBracket
    let tierNumber: Int
    let minHours: Int
    let canDelete: Bool
    let onDelete: () -> Void

    private var maxHours: Double { Double(PolicyLeadTimeFormatter.maxPolicyHours) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("Tier \(tierNumber)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Brand.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Brand.accent.opacity(0.13), in: Capsule())
                Spacer()
                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Brand.danger.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                }
            }

            PolicySliderRow(
                label: "Time before shift",
                value: Binding(
                    get: { Double(bracket.hoursBeforeStart) },
                    set: { bracket.hoursBeforeStart = max(Int($0), minHours) }
                ),
                range: Double(minHours)...maxHours,
                step: 1,
                format: { PolicyLeadTimeFormatter.formatSliderHours(Int($0)) }
            )

            PolicySliderRow(
                label: "Penalty",
                value: Binding(
                    get: { bracket.penaltyPercent * 100 },
                    set: { bracket.penaltyPercent = $0 / 100 }
                ),
                range: 100...500,
                step: 5,
                format: { "\(Int($0))% of base" }
            )
        }
    }
}

// MARK: - Add Timeframe Sheet

private struct AddCancellationTimeframeSheet: View {
    @Binding var scale: [SchedulingPolicy.PenaltyBracket]
    let minHours: Int
    @Environment(\.dismiss) private var dismiss
    @State private var hours: Double
    @State private var percent: Double = 200

    init(scale: Binding<[SchedulingPolicy.PenaltyBracket]>, minHours: Int) {
        self._scale = scale
        self.minHours = minHours
        self._hours = State(initialValue: Double(minHours))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundGradient()
                VStack(spacing: 12) {
                    Text("Set the lead time and penalty for the new tier. The time minimum starts where your last tier left off.")
                        .font(.system(size: 13))
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    PolicySliderRow(
                        label: "Time before shift",
                        value: $hours,
                        range: Double(minHours)...Double(PolicyLeadTimeFormatter.maxPolicyHours),
                        step: 1,
                        format: { PolicyLeadTimeFormatter.formatSliderHours(Int($0)) }
                    )
                    .cardStyle()

                    PolicySliderRow(
                        label: "Penalty",
                        value: $percent,
                        range: 100...500,
                        step: 5,
                        format: { "\(Int($0))% of base" }
                    )
                    .cardStyle()

                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
            }
            .navigationTitle("New Tier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Brand.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        scale.append(SchedulingPolicy.PenaltyBracket(
                            hoursBeforeStart: Int(hours),
                            penaltyPercent: percent / 100
                        ))
                        scale = SchedulingPolicy.normalizeCancellationScale(scale)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.accent)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationCornerRadius(28)
    }
}

// MARK: - Trade Penalty Editor

private struct TradePenaltyEditor: View {
    @Binding var policy: SchedulingPolicy

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeader(title: "Trade Penalties", systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                Toggle("", isOn: $policy.tradePenaltiesEnabled)
                    .labelsHidden()
                    .tint(Brand.accent)
            }

            if policy.tradePenaltiesEnabled {
                SubtleDivider()

                Text("A flat fee applies when a trade occurs inside the lead-time window before the shift.")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                PolicySliderRow(
                    label: "Fee amount",
                    value: Binding(
                        get: { Double(truncating: policy.tradePenaltyAmount as NSNumber) },
                        set: { policy.tradePenaltyAmount = Decimal($0) }
                    ),
                    range: 0...2000,
                    step: 25,
                    format: { "$\(Int($0))" }
                )

                PolicySliderRow(
                    label: "Window before shift",
                    value: Binding(
                        get: { Double(policy.tradePenaltyHoursBeforeStart) },
                        set: { policy.tradePenaltyHoursBeforeStart = Int($0) }
                    ),
                    range: 0...Double(PolicyLeadTimeFormatter.maxPolicyHours),
                    step: 1,
                    format: { PolicyLeadTimeFormatter.beforeShiftLabel(hours: Int($0)) }
                )
            } else {
                Text("Trades incur no fee.")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.textSecondary)
            }
        }
        .cardStyle()
    }
}

// MARK: - Doctor My Shifts (cancel + trade)

struct MyAssignedShiftsView: View {
    @StateObject private var store = AssignedShiftsStore.shared
    @State private var actionMessage: String?
    @State private var tradeExpandedID: UUID? = nil
    @State private var cancelExpandedID: UUID? = nil

    private var activeShifts: [AssignedShiftsStore.AssignedShift] { store.activeAssignedShifts() }

    var body: some View {
        ZStack {
            BackgroundGradient()
            ScrollView {
                VStack(spacing: 14) {
                    if !store.incomingTrades.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Incoming Trade Requests", systemImage: "tray.and.arrow.down.fill")
                            ForEach(store.incomingTrades) { trade in
                                IncomingTradeRow(trade: trade) { accept in
                                    Task {
                                        do {
                                            let penalty = try await store.respondToTrade(trade, accept: accept)
                                            let fee = NSDecimalNumber(decimal: penalty).intValue
                                            actionMessage = accept
                                                ? (fee > 0 ? "Trade accepted · $\(fee) fee" : "Trade accepted")
                                                : "Trade declined"
                                        } catch {
                                            actionMessage = error.localizedDescription
                                        }
                                    }
                                }
                                if trade.id != store.incomingTrades.last?.id { Divider() }
                            }
                        }
                        .cardStyle()
                    }

                    let active = activeShifts
                    if active.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.clock").font(.system(size: 44)).foregroundStyle(.secondary)
                            Text("No assigned shifts").font(.headline).foregroundStyle(.secondary)
                            Text("Accept shifts from the marketplace to manage them here.")
                                .font(.subheadline).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(40)
                    } else {
                        ForEach(active) { assigned in
                            AssignedShiftCard(
                                assigned: assigned,
                                store: store,
                                tradeExpandedID: $tradeExpandedID,
                                cancelExpandedID: $cancelExpandedID
                            ) { msg in actionMessage = msg }
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.97)),
                                removal:   .opacity.combined(with: .scale(scale: 0.94))
                            ))
                        }
                    }

                    if let msg = actionMessage {
                        Text(msg).font(.caption).foregroundStyle(.secondary).cardStyle()
                    }
                }
                .padding()
            }
        }
        .navigationTitle("My Shifts")
        .onAppear {
            store.seedMockShiftsIfNeeded()
            store.seedMockIncomingTradesIfNeeded()
            DoctorRosterStore.shared.seedMockDoctorsIfNeeded()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { store.resetMockData() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
        }
    }
}

private struct AssignedShiftCard: View {
    let assigned: AssignedShiftsStore.AssignedShift
    @ObservedObject var store: AssignedShiftsStore
    @Binding var tradeExpandedID: UUID?
    @Binding var cancelExpandedID: UUID?
    let onAction: (String) -> Void

    @State private var selectedDoctor: DoctorSummary?
    @State private var tradeSending = false
    @State private var tradeSent = false
    @State private var tradeError: String?
    @State private var cancelSending = false
    @State private var cancelConfirmed = false

    private var isTradeExpanded: Bool { tradeExpandedID == assigned.id }
    private var isCancelExpanded: Bool { cancelExpandedID == assigned.id }

    private var partners: [DoctorSummary] {
        DoctorRosterStore.shared.eligibleTradePartners(
            for: assigned.shift.specialty,
            excluding: assigned.doctorID
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            ShiftRow(shift: assigned.shift, showLockBadge: true)
            if assigned.status == .tradedPending {
                Label("Trade pending approval", systemImage: "hourglass")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12), in: Capsule())
            }

            Divider().opacity(0.4)

            // Action buttons
            HStack(spacing: 10) {
                // Trade button
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        cancelExpandedID = nil
                        if isTradeExpanded {
                            tradeExpandedID = nil
                            selectedDoctor = nil; tradeError = nil
                        } else {
                            tradeExpandedID = assigned.id
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isTradeExpanded ? "chevron.up" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                        Text(isTradeExpanded ? "Close" : "Trade Shift")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(isTradeExpanded ? Color.secondary : Color.accentColor)
                .disabled(assigned.status == .tradedPending)

                // Cancel button
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        tradeExpandedID = nil
                        selectedDoctor = nil; tradeError = nil
                        if isCancelExpanded {
                            cancelExpandedID = nil
                        } else {
                            cancelExpandedID = assigned.id
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCancelExpanded ? "chevron.up" : "xmark.circle")
                            .font(.system(size: 13, weight: .semibold))
                        Text(isCancelExpanded ? "Close" : "Cancel")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .tint(isCancelExpanded ? Color.secondary : Color.red)
            }

            // Trade expansion panel
            if isTradeExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    if partners.isEmpty {
                        Text("No eligible doctors available for this specialty.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("Choose a doctor to offer the trade to:")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(partners) { doc in
                            Button {
                                withAnimation { selectedDoctor = doc }
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(selectedDoctor?.id == doc.id
                                                  ? Color.accentColor.opacity(0.2)
                                                  : Color.white.opacity(0.06))
                                            .frame(width: 36, height: 36)
                                        Text(String(doc.name.split(separator: " ").last?.prefix(2) ?? "Dr"))
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(selectedDoctor?.id == doc.id ? Color.accentColor : .secondary)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(doc.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                        Text("\(doc.credential) · \(doc.specialty)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedDoctor?.id == doc.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentColor)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .padding(10)
                                .background(
                                    selectedDoctor?.id == doc.id
                                        ? Color.accentColor.opacity(0.08)
                                        : Color.white.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let err = tradeError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }

                    Button { sendTrade() } label: {
                        HStack {
                            if tradeSending {
                                ProgressView().tint(.white).scaleEffect(0.8)
                            } else if tradeSent {
                                Label("Request Sent!", systemImage: "checkmark.circle.fill")
                            } else {
                                Text("Send Trade Request")
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selectedDoctor == nil || tradeSending || tradeSent || partners.isEmpty)
                }
                .padding(12)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Cancel expansion panel
            if isCancelExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    if cancelConfirmed {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Brand.danger)
                            Text("Shift Canceled")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Brand.danger)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .transition(.scale(scale: 1.0).combined(with: .opacity))
                    } else {
                        Text("Are you sure you want to cancel this shift?")
                            .font(.subheadline.weight(.medium)).foregroundStyle(.primary)

                        let penalty = store.preview(for: .cancel, assigned: assigned).penaltyAmount
                        if penalty > 0 {
                            Label("Cancellation fee: $\(NSDecimalNumber(decimal: penalty).intValue)",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                        } else {
                            Label("No penalty at this time", systemImage: "checkmark.circle")
                                .font(.caption).foregroundStyle(.green)
                        }

                        HStack(spacing: 10) {
                            Button {
                                withAnimation { cancelExpandedID = nil }
                            } label: {
                                Text("Keep Shift")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                            }
                            .buttonStyle(.bordered).tint(Color.accentColor)

                            Button { doCancel() } label: {
                                HStack {
                                    if cancelSending { ProgressView().tint(.white).scaleEffect(0.8) }
                                    else { Text("Yes, Cancel") }
                                }
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                            }
                            .buttonStyle(.bordered).tint(.red)
                            .disabled(cancelSending)
                        }
                    }
                }
                .padding(12)
                .background(
                    cancelConfirmed ? Color.red.opacity(0.10) : Color.red.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 12)
                )
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.2), lineWidth: 1))
                .scaleEffect(cancelConfirmed ? 1.03 : 1.0)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: isTradeExpanded)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: isCancelExpanded)
    }

    private func sendTrade() {
        guard let doctor = selectedDoctor else { return }
        tradeSending = true; tradeError = nil
        Task {
            do {
                _ = try await store.requestTrade(for: assigned, toDoctor: doctor)
                tradeSent = true
                try await Task.sleep(nanoseconds: 1_200_000_000)
                withAnimation { tradeExpandedID = nil }
            } catch {
                tradeError = error.localizedDescription
            }
            tradeSending = false
        }
    }

    private func doCancel() {
        cancelSending = true
        Task {
            do {
                let penalty = try await store.cancelShift(assigned)
                // Show confirmed state — card expands briefly then folds away
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    cancelConfirmed = true
                    cancelSending = false
                }
                let msg = penalty > 0
                    ? "Shift canceled · $\(NSDecimalNumber(decimal: penalty).intValue) penalty"
                    : "Shift canceled"
                try await Task.sleep(nanoseconds: 1_100_000_000)
                // Card is removed from activeAssignedShifts — parent ForEach animates it out
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    cancelExpandedID = nil
                }
                onAction(msg)
            } catch {
                onAction(error.localizedDescription)
                cancelSending = false
            }
        }
    }
}


private struct PolicyChip: View {
    let label: String
    let preview: PolicyPreview

    private var feeText: String {
        guard preview.allowed else { return "Blocked" }
        if preview.penaltyAmount > 0 {
            return "$\(NSDecimalNumber(decimal: preview.penaltyAmount).intValue) fee"
        }
        return "Free"
    }

    private var feeColor: Color {
        guard preview.allowed else { return .red }
        return preview.penaltyAmount > 0 ? .orange : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(feeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(feeColor)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct IncomingTradeRow: View {
    let trade: ShiftTradeRequest
    let onRespond: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Shift trade request").font(.headline)
                Text(trade.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { onRespond(true) } label: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title2)
            }
            Button { onRespond(false) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red).font(.title2)
            }
        }
    }
}

struct TradeShiftSheet: View {
    let assigned: AssignedShiftsStore.AssignedShift
    let partners: [DoctorSummary]
    @ObservedObject var store: AssignedShiftsStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDoctor: DoctorSummary?
    @State private var errorMessage: String?
    @State private var didSend = false

    private var tradePreview: PolicyPreview { store.preview(for: .trade, assigned: assigned) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ShiftRow(shift: assigned.shift).cardStyle()

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Trade Policy", systemImage: "doc.text")
                        if tradePreview.allowed {
                            if tradePreview.penaltyAmount > 0 {
                                Text("Fee if accepted: $\(NSDecimalNumber(decimal: tradePreview.penaltyAmount).intValue) (\(Int(tradePreview.penaltyPercent * 100))%)")
                                    .font(.subheadline).foregroundStyle(.orange)
                            } else {
                                Text("No trade fee at this time.").font(.subheadline).foregroundStyle(.green)
                            }
                        } else {
                            Text(tradePreview.blockedReason ?? "Trading not allowed").font(.subheadline).foregroundStyle(.red)
                        }
                    }
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Select Doctor", systemImage: "person.2.fill")
                        if partners.isEmpty {
                            Text("No eligible doctors in this specialty.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            ForEach(partners) { doc in
                                Button {
                                    selectedDoctor = doc
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(doc.name).font(.headline)
                                            Text(doc.specialty).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if selectedDoctor?.id == doc.id {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                if doc.id != partners.last?.id { Divider() }
                            }
                        }
                    }
                    .cardStyle()

                    if let err = errorMessage {
                        Text(err).font(.caption).foregroundStyle(.red).cardStyle()
                    }

                    Button {
                        sendTrade()
                    } label: {
                        Group {
                            if didSend { Label("Request Sent!", systemImage: "checkmark.circle.fill") }
                            else { Text("Send Trade Request") }
                        }
                        .font(.headline).frame(maxWidth: .infinity).padding()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selectedDoctor == nil || !tradePreview.allowed || didSend)
                }
                .padding()
            }
            .background(Brand.bg.ignoresSafeArea())
            .navigationTitle("Trade Shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
            }
        }
        .presentationCornerRadius(24)
    }

    private func sendTrade() {
        guard let doctor = selectedDoctor else { return }
        Task {
            do {
                _ = try await store.requestTrade(for: assigned, toDoctor: doctor)
                didSend = true
                try await Task.sleep(nanoseconds: 900_000_000)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Cancel Confirm Sheet

struct CancelShiftConfirmSheet: View {
    let assigned: AssignedShiftsStore.AssignedShift
    let penalty: Decimal
    let onDecide: (Bool) -> Void

    @State private var acknowledged = false
    @State private var pulse = false

    private var shift: Shift { assigned.shift }
    private var hasPenalty: Bool { penalty > 0 }
    private var penaltyInt: Int { NSDecimalNumber(decimal: penalty).intValue }

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.04, blue: 0.04).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {

                    // Header icon
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 110, height: 110)
                            .scaleEffect(pulse ? 1.12 : 1.0)
                            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
                        Image(systemName: "heart.slash.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.red)
                    }
                    .padding(.top, 48)
                    .onAppear { pulse = true }

                    Text("Someone needs you here.")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                        .padding(.horizontal, 28)

                    Text("This shift is filled — by you — because a real patient will need a doctor that day. Canceling doesn't just free up your calendar. It creates a gap in care that may not be filled in time.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                        .padding(.horizontal, 28)

                    // Shift info card
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "building.2.fill")
                                .foregroundStyle(Color.white.opacity(0.4))
                            Text(shift.hospital)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        HStack {
                            Image(systemName: "stethoscope")
                                .foregroundStyle(Color.white.opacity(0.4))
                            Text(shift.specialty)
                                .font(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.8))
                        }
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(Color.white.opacity(0.4))
                            Text(shift.displayDateLabel)
                                .font(.subheadline)
                                .foregroundStyle(Color.white.opacity(0.8))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.red.opacity(0.3), lineWidth: 1))
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                    // Penalty warning
                    if hasPenalty {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cancellation penalty: $\(penaltyInt)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.orange)
                                Text("Per hospital policy. Charged immediately upon cancellation.")
                                    .font(.caption)
                                    .foregroundStyle(Color.white.opacity(0.5))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                        .padding(.horizontal, 24)
                        .padding(.top, 14)
                    }

                    // Acknowledgment checkbox
                    Button {
                        withAnimation(.spring(response: 0.25)) { acknowledged.toggle() }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(acknowledged ? Color.red : Color.white.opacity(0.3), lineWidth: 1.5)
                                    .frame(width: 22, height: 22)
                                if acknowledged {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.red)
                                }
                            }
                            Text("I understand that canceling this shift may leave a patient without a physician and could affect the quality of care they receive.")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    // Action buttons
                    VStack(spacing: 10) {
                        Button {
                            onDecide(false)
                        } label: {
                            Text("Keep My Shift")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(Brand.accent, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)

                        Button {
                            guard acknowledged else { return }
                            onDecide(true)
                        } label: {
                            Text("Cancel Shift Anyway")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    acknowledged
                                        ? Color.red.opacity(0.20)
                                        : Color.white.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 14)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(acknowledged ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
                                )
                                .foregroundStyle(acknowledged ? Color.red : Color.white.opacity(0.25))
                        }
                        .buttonStyle(.plain)
                        .disabled(!acknowledged)

                        if !acknowledged {
                            Text("Check the box above to confirm you understand the impact.")
                                .font(.caption2)
                                .foregroundStyle(Color.white.opacity(0.3))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .presentationCornerRadius(24)
        .presentationDetents([.large])
    }
}
