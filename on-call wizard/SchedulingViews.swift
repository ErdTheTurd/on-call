import SwiftUI
import UIKit

// MARK: - Hospital On Call Settings

struct HospitalPolicySettingsView: View {
    let hospitalProfile: HospitalProfile?
    @StateObject private var policyStore = SchedulingPolicyStore.shared
    @State private var didSave = false
    @State private var selectedTab: OnCallSettingsTab = .general

    private enum OnCallSettingsTab: String, CaseIterable {
        case general = "General"
        case cancellation = "Cancellation"
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
        .navigationTitle("Scheduling")
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

            // Daily request tokens
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Daily Tokens", systemImage: "ticket.fill")
                Text("How many coverage requests each physician can make per day. Raise or lower individuals on the Doctors tab.")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                PolicySliderRow(
                    label: "Roster default",
                    value: Binding(
                        get: { Double(policyStore.policy.defaultDailyTokens) },
                        set: { policyStore.policy.defaultDailyTokens = SchedulingPolicy.clampDailyTokens(Int($0)) }
                    ),
                    range: Double(SchedulingPolicy.minDailyTokens)...Double(SchedulingPolicy.maxDailyTokens),
                    step: 1,
                    format: { "\(Int($0)) / day" }
                )
                if let hospitalID = hospitalProfile?.id {
                    Divider().opacity(0.35)
                    Text("Per-doctor exceptions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(DoctorRosterStore.shared.doctors) { doc in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(doc.name).font(.subheadline.weight(.medium))
                                Text(doc.specialty).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            DoctorTokenAllowanceStepper(hospitalID: hospitalID, doctorID: doc.id, compact: true)
                        }
                        .padding(.vertical, 4)
                    }
                }
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
                    range: 0...2000,
                    step: 25,
                    format: { NumberFormat.currency($0) }
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
}

// MARK: - Specialty pay editor

struct SpecialtyPayEditor: View {
    @Binding var policy: SchedulingPolicy
    @ObservedObject private var roster = DoctorRosterStore.shared
    @State private var expandedSpecialty: String? = nil
    @State private var selectedSpecialties: Set<String> = []
    @State private var globalBasePay: Double = 500

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

    private var allSelected: Bool {
        !specialties.isEmpty && specialties.allSatisfy { selectedSpecialties.contains($0) }
    }

    private func doctors(for specialty: String) -> [DoctorSummary] {
        useMockData
            ? Self.mockDoctors.filter { $0.specialty == specialty }
            : roster.doctors.filter { $0.specialty == specialty }
    }

    private func rate(for specialty: String) -> Double {
        policy.specialtyBaseRates[specialty]
            ?? Self.mockSpecialtyRates[specialty]
            ?? Self.defaultRate
    }

    private func applyBasePay(_ newRate: Double, to targets: [String]) {
        for sp in targets {
            policy.specialtyBaseRates[sp] = newRate
            for doc in doctors(for: sp) {
                policy.doctorBaseRates[doc.id.uuidString] = newRate
            }
        }
    }

    private func applyPricingMode(_ useAlgorithm: Bool, to targets: [String]) {
        policy.setUsesAlgorithmPricing(useAlgorithm, forSpecialties: targets)
        if targets.count == specialties.count {
            policy.useAlgorithmPricingByDefault = useAlgorithm
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            // Global controls
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Base Pay per Shift", systemImage: "dollarsign.circle.fill")
                Text("1) Choose which specialties to update. 2) Pick Auto or Set rates. 3) Drag the slider to set pay for that selection.")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ApplyToSpecialtiesBar(
                    selectedCount: selectedSpecialties.count,
                    totalCount: specialties.count,
                    allSelected: allSelected,
                    onSelectAll: { selectedSpecialties = Set(specialties) },
                    onClear: { selectedSpecialties.removeAll() }
                )

                PricingModePicker(
                    useAlgorithm: Binding(
                        get: {
                            let targets = selectedSpecialties.isEmpty ? specialties : Array(selectedSpecialties)
                            guard !targets.isEmpty else { return policy.useAlgorithmPricingByDefault }
                            return targets.allSatisfy { policy.usesAlgorithmPricing(for: $0) }
                        },
                        set: { useAlgo in
                            let targets = selectedSpecialties.isEmpty ? specialties : Array(selectedSpecialties)
                            applyPricingMode(useAlgo, to: targets.isEmpty ? specialties : targets)
                        }
                    )
                )

                PolicySliderRow(
                    label: selectedSpecialties.isEmpty
                        ? "Base pay (select specialties first)"
                        : allSelected
                            ? "Base pay · all specialties"
                            : "Base pay · \(selectedSpecialties.count) selected",
                    value: Binding(
                        get: { globalBasePay },
                        set: { newValue in
                            globalBasePay = newValue
                            let targets = selectedSpecialties.isEmpty ? specialties : Array(selectedSpecialties)
                            applyBasePay(newValue, to: targets)
                        }
                    ),
                    range: 100...5000,
                    step: 25,
                    format: { NumberFormat.currency($0) }
                )
                .opacity(selectedSpecialties.isEmpty ? 0.45 : 1)
                .disabled(selectedSpecialties.isEmpty)
            }
            .cardStyle()

            ForEach(specialties, id: \.self) { specialty in
                let usesAlgo = policy.usesAlgorithmPricing(for: specialty)
                SpecialtyPayRow(
                    specialty: specialty,
                    doctors: doctors(for: specialty),
                    specialtyRate: Binding(
                        get: { rate(for: specialty) },
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
                    },
                    isSelected: Binding(
                        get: { selectedSpecialties.contains(specialty) },
                        set: { on in
                            if on { selectedSpecialties.insert(specialty) }
                            else { selectedSpecialties.remove(specialty) }
                        }
                    ),
                    useAlgorithm: Binding(
                        get: { usesAlgo },
                        set: { policy.setUsesAlgorithmPricing($0, for: specialty) }
                    )
                )
            }
        }
        .onAppear {
            let rates = specialties.map { rate(for: $0) }
            if let first = rates.first, rates.allSatisfy({ abs($0 - first) < 1 }) {
                globalBasePay = first
            } else if let avg = rates.isEmpty ? nil : rates.reduce(0, +) / Double(rates.count) {
                globalBasePay = (avg / 25).rounded() * 25
            }
            if selectedSpecialties.isEmpty {
                selectedSpecialties = Set(specialties)
            }
        }
    }
}

// MARK: - Apply-to bar (replaces bare “select all” checkmark)

private struct ApplyToSpecialtiesBar: View {
    let selectedCount: Int
    let totalCount: Int
    let allSelected: Bool
    let onSelectAll: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apply changes to")
                .font(.caption.weight(.bold))
                .foregroundStyle(Brand.textTertiary)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                Image(systemName: allSelected ? "checkmark.circle.fill" : selectedCount > 0 ? "circle.lefthalf.filled" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selectedCount > 0 ? Brand.accent : Brand.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(allSelected
                         ? "All \(totalCount) specialties"
                         : selectedCount == 0
                            ? "None selected"
                            : "\(selectedCount) of \(totalCount) specialties")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Brand.textPrimary)
                    Text("Check specialties below, or use Select all.")
                        .font(.system(size: 12))
                        .foregroundStyle(Brand.textSecondary)
                }

                Spacer(minLength: 8)

                Button(allSelected ? "Clear" : "Select all") {
                    if allSelected { onClear() } else { onSelectAll() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.accent)
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Brand.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

// MARK: - Auto / Set rates picker (labeled, not a mystery toggle)

private struct PricingModePicker: View {
    @Binding var useAlgorithm: Bool

    private enum Mode: String, CaseIterable, Identifiable {
        case auto, setRates
        var id: String { rawValue }
        var title: String { self == .auto ? "Auto" : "Set rates" }
    }

    private var mode: Binding<Mode> {
        Binding(
            get: { useAlgorithm ? .auto : .setRates },
            set: { useAlgorithm = ($0 == .auto) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pricing mode")
                .font(.caption.weight(.bold))
                .foregroundStyle(Brand.textTertiary)
                .textCase(.uppercase)

            Picker("Pricing mode", selection: mode) {
                Text("Auto").tag(Mode.auto)
                Text("Set rates").tag(Mode.setRates)
            }
            .pickerStyle(.segmented)

            HStack(alignment: .top, spacing: 12) {
                modeBlurb(
                    icon: "sparkles",
                    title: "Auto",
                    body: "On Call algorithm prices selected specialties for you.",
                    active: useAlgorithm
                )
                modeBlurb(
                    icon: "slider.horizontal.3",
                    title: "Set rates",
                    body: "You set the dollar amounts with the slider and per-specialty rows.",
                    active: !useAlgorithm
                )
            }
        }
    }

    private func modeBlurb(icon: String, title: String, body: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(active ? Brand.accent : Brand.textTertiary)
            Text(body)
                .font(.caption2)
                .foregroundStyle(active ? Brand.textSecondary : Brand.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            (active ? Brand.accentSoft : Color.white.opacity(0.04)),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(active ? Brand.accent.opacity(0.35) : Color.clear, lineWidth: 1)
        )
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
    @Binding var isSelected: Bool
    @Binding var useAlgorithm: Bool

    @State private var justReset = false

    private enum RowMode: String, CaseIterable, Identifiable {
        case auto, setRates
        var id: String { rawValue }
    }

    private var rowMode: Binding<RowMode> {
        Binding(
            get: { useAlgorithm ? .auto : .setRates },
            set: { useAlgorithm = ($0 == .auto) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Include in bulk + header ─────────────────────
            HStack(alignment: .center, spacing: 10) {
                Button {
                    isSelected.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(isSelected ? Brand.accent : Brand.textTertiary)
                        Text(isSelected ? "Included" : "Include")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? Brand.accent : Brand.textTertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        isSelected ? Brand.accentSoft : Color.white.opacity(0.04),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? "\(specialty) included in bulk edits" : "Include \(specialty) in bulk edits")

                Spacer(minLength: 4)

                Button(action: onToggle) {
                    HStack(spacing: 8) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(specialty)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Brand.textPrimary)
                            Text(doctors.isEmpty ? "No doctors registered" : "\(doctors.count) doctor\(doctors.count == 1 ? "" : "s")")
                                .font(.system(size: 12))
                                .foregroundStyle(Brand.textSecondary)
                        }
                        if !doctors.isEmpty {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Brand.textTertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            // ── Mode: clear segmented labels ─────────────────
            VStack(alignment: .leading, spacing: 6) {
                Text("How this specialty is priced")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Brand.textTertiary)
                    .textCase(.uppercase)
                    .padding(.top, 14)

                Picker("Pricing", selection: rowMode) {
                    Text("Auto").tag(RowMode.auto)
                    Text("Set rates").tag(RowMode.setRates)
                }
                .pickerStyle(.segmented)

                Text(useAlgorithm
                     ? "Algorithm sets this specialty’s rates automatically."
                     : "You set the dollar amount for this specialty below.")
                    .font(.caption)
                    .foregroundStyle(Brand.textSecondary)
            }

            if useAlgorithm {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Brand.accent)
                    Text("Auto mode — switch to Set rates to edit dollars.")
                        .font(.system(size: 12))
                        .foregroundStyle(Brand.textSecondary)
                }
                .padding(.top, 10)
            } else {
                HStack {
                    Text("Specialty base")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Brand.textPrimary)
                    Spacer()
                    ValueChip(text: NumberFormat.currency(specialtyRate))
                }
                .padding(.top, 12)

                Slider(value: $specialtyRate, in: 100...5000, step: 25,
                       onEditingChanged: { editing in
                           guard !editing, !doctors.isEmpty else { return }
                           withAnimation(.easeInOut(duration: 0.2)) { justReset = true }
                           DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                               withAnimation { justReset = false }
                           }
                       })
                .tint(Brand.accent)
                .padding(.top, 8)

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
                                    ValueChip(text: NumberFormat.currency(doctorRate(doctor)))
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
                .strokeBorder(
                    isSelected ? Brand.accent.opacity(0.45) : Brand.border.opacity(0.9),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isExpanded)
        .animation(.easeOut(duration: 0.2), value: useAlgorithm)
        .animation(.easeOut(duration: 0.2), value: isSelected)
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
                    format: { NumberFormat.currency($0) }
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
    @ObservedObject private var store = AssignedShiftsStore.shared
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
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Incoming Trade Requests", systemImage: "tray.and.arrow.down.fill")
                            ForEach(store.incomingTrades) { trade in
                                IncomingTradeRow(trade: trade, store: store) { message in
                                    actionMessage = message
                                }
                                if trade.id != store.incomingTrades.last?.id {
                                    Divider().opacity(0.35)
                                }
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
    @State private var selectedPartnerShift: AssignedShiftsStore.AssignedShift?
    @State private var compensation: Double = 0
    @State private var tradeSending = false
    @State private var tradeSent = false
    @State private var tradeError: String?
    @State private var sendPulse = false
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

    private var partnerDays: [AssignedShiftsStore.AssignedShift] {
        guard let doc = selectedDoctor else { return [] }
        return store.tradeableShifts(
            forPartner: doc.id,
            specialty: assigned.shift.specialty,
            excludingDate: assigned.shift.date
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

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        cancelExpandedID = nil
                        if isTradeExpanded {
                            resetTradeForm()
                            tradeExpandedID = nil
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

                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        tradeExpandedID = nil
                        resetTradeForm()
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

            if isTradeExpanded {
                tradePanel
                    .padding(12)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if isCancelExpanded {
                cancelPanel
            }
        }
        .cardStyle()
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: isTradeExpanded)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: isCancelExpanded)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: selectedDoctor?.id)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: selectedPartnerShift?.id)
    }

    @ViewBuilder
    private var tradePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if tradeSent {
                tradeSuccessBanner
            } else {
                Text("1. Choose a doctor")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if partners.isEmpty {
                    Text("No eligible doctors available for this specialty.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(partners) { doc in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                selectedDoctor = doc
                                selectedPartnerShift = nil
                                tradeError = nil
                            }
                            store.preparePartnerTradeDays(
                                forPartner: doc.id,
                                specialty: assigned.shift.specialty,
                                excludingDate: assigned.shift.date
                            )
                        } label: {
                            doctorPickRow(doc)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if selectedDoctor != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("2. Pick their day (you get this)")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("You give up \(assigned.shift.displayDateLabel).")
                            .font(.caption2).foregroundStyle(.tertiary)
                        TradePartnerCalendar(
                            days: partnerDays,
                            selected: $selectedPartnerShift
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("3. Your offer")
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            Text(NumberFormat.currency(compensation))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.accentColor)
                                .contentTransition(.numericText())
                        }
                        Slider(value: $compensation, in: 0...1_000, step: 25)
                            .tint(Color.accentColor)
                        Text("Optional · $0–$1,000")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .transition(.opacity)
                }

                if let err = tradeError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }

                Button { sendTrade() } label: {
                    HStack(spacing: 8) {
                        if tradeSending {
                            ProgressView().tint(.white).scaleEffect(0.8)
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text("Send Trade Request")
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .scaleEffect(sendPulse ? 1.04 : 1)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedDoctor == nil || selectedPartnerShift == nil || tradeSending || partners.isEmpty)
            }
        }
    }

    private var tradeSuccessBanner: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: tradeSent)
                .scaleEffect(sendPulse ? 1.15 : 1)
            Text("Trade request sent")
                .font(.headline.weight(.bold))
            if let doc = selectedDoctor, let day = selectedPartnerShift {
                Text("Offered \(assigned.shift.displayDateLabel) ↔ \(day.shift.displayDateLabel) with \(doc.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if compensation > 0 {
                Text("+\(NumberFormat.currency(compensation)) compensation")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func doctorPickRow(_ doc: DoctorSummary) -> some View {
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

    @ViewBuilder
    private var cancelPanel: some View {
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
                    Label("Cancellation fee: \(NumberFormat.currency(NSDecimalNumber(decimal: penalty).intValue))",
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

    private func resetTradeForm() {
        selectedDoctor = nil
        selectedPartnerShift = nil
        compensation = 0
        tradeError = nil
        tradeSent = false
        tradeSending = false
        sendPulse = false
    }

    private func sendTrade() {
        guard let doctor = selectedDoctor, let wanted = selectedPartnerShift else {
            tradeError = TradeError.missingRequestedDay.localizedDescription
            return
        }
        tradeSending = true
        tradeError = nil
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { sendPulse = true }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            do {
                _ = try await store.requestTrade(
                    for: assigned,
                    toDoctor: doctor,
                    requestedShift: wanted,
                    compensationAmount: compensation
                )
                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                    tradeSent = true
                    sendPulse = true
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                try await Task.sleep(nanoseconds: 1_400_000_000)
                withAnimation {
                    tradeExpandedID = nil
                    resetTradeForm()
                }
                onAction("Trade sent to \(doctor.name)")
            } catch {
                withAnimation { sendPulse = false }
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    cancelConfirmed = true
                    cancelSending = false
                }
                let msg = penalty > 0
                    ? "Shift canceled · \(NumberFormat.currency(NSDecimalNumber(decimal: penalty).intValue)) penalty"
                    : "Shift canceled"
                try await Task.sleep(nanoseconds: 1_100_000_000)
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

/// Compact calendar of tradeable days (yours or a partner's).
private struct TradePartnerCalendar: View {
    let days: [AssignedShiftsStore.AssignedShift]
    @Binding var selected: AssignedShiftsStore.AssignedShift?
    var selectionLabel: String = "Get"

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private var monthDays: [(date: Date, shift: AssignedShiftsStore.AssignedShift?)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 41, to: today) else { return [] }
        var byDay: [Date: AssignedShiftsStore.AssignedShift] = [:]
        for day in days {
            byDay[cal.startOfDay(for: day.shift.date)] = day
        }
        var result: [(Date, AssignedShiftsStore.AssignedShift?)] = []
        var cursor = today
        while cursor <= end {
            result.append((cursor, byDay[cursor]))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if days.isEmpty {
                Text("No upcoming scheduled days.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, w in
                        Text(w)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(Array(monthDays.enumerated()), id: \.offset) { _, item in
                        let isSelected = selected?.id == item.shift?.id
                        let available = item.shift != nil
                        Button {
                            guard let shift = item.shift else { return }
                            selected = shift
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            Text("\(Calendar.current.component(.day, from: item.date))")
                                .font(.system(size: 12, weight: available ? .bold : .regular))
                                .foregroundStyle(
                                    isSelected ? Color.white
                                    : available ? Color.primary
                                    : Color.secondary.opacity(0.35)
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(
                                            isSelected ? Color.accentColor
                                            : available ? Color.accentColor.opacity(0.14)
                                            : Color.clear
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!available)
                    }
                }
                if let sel = selected {
                    Label("\(selectionLabel) \(sel.shift.displayDateLabel)", systemImage: "arrow.left.arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct PolicyChip: View {
    let label: String
    let preview: PolicyPreview

    private var feeText: String {
        guard preview.allowed else { return "Blocked" }
        if preview.penaltyAmount > 0 {
            return "\(NumberFormat.currency(NSDecimalNumber(decimal: preview.penaltyAmount).intValue)) fee"
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
    @ObservedObject var store: AssignedShiftsStore
    let onMessage: (String) -> Void

    @State private var showCounter = false
    @State private var counterDays: [AssignedShiftsStore.AssignedShift] = []
    @State private var counterShift: AssignedShiftsStore.AssignedShift?
    @State private var counterComp: Double = 0
    @State private var busy = false
    @State private var doneMessage: String?
    @State private var errorText: String?

    private var fromName: String {
        trade.fromDoctorName ?? store.doctorName(for: trade.fromDoctorID)
    }

    private var theirDay: String {
        if let d = trade.offeredDate {
            return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return "their shift"
    }

    private var myDay: String {
        if let d = trade.requestedDate {
            return d.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return "your shift"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let doneMessage {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    Text(doneMessage)
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fromName)
                            .font(.headline)
                        Text("Wants \(theirDay) ↔ your \(myDay)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if trade.compensationAmount > 0 {
                            Text("Offers \(NumberFormat.currency(trade.compensationAmount))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Text("No compensation offered")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        if trade.counterOfTradeID != nil {
                            Text("Counter offer")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if let err = errorText {
                    Text(err).font(.caption).foregroundStyle(.red)
                }

                if showCounter {
                    counterPanel
                } else {
                    HStack(spacing: 8) {
                        Button {
                            respond(accept: true)
                        } label: {
                            Label("Accept", systemImage: "checkmark")
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(busy)

                        Button {
                            openCounter()
                        } label: {
                            Label("Counter", systemImage: "arrow.2.squarepath")
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accentColor)
                        .disabled(busy)

                        Button {
                            respond(accept: false)
                        } label: {
                            Label("Decline", systemImage: "xmark")
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(busy)
                    }
                }
            }
        }
    }

    private var counterPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your calendar · pick a day to give")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TradePartnerCalendar(days: counterDays, selected: $counterShift, selectionLabel: "Give")

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Ask them for")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(NumberFormat.currency(counterComp))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .contentTransition(.numericText())
                }
                Slider(value: $counterComp, in: 0...1_000, step: 25)
                    .tint(Color.accentColor)
                Text(counterCompHint)
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                Button {
                    showCounter = false
                    errorText = nil
                } label: {
                    Text("Back")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(busy)

                Button {
                    sendCounter()
                } label: {
                    Group {
                        if busy {
                            ProgressView().scaleEffect(0.75)
                        } else {
                            Text("Send Counter")
                        }
                    }
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || counterShift == nil)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    /// The counter keeps them as the requester, so this amount is what they pay you.
    private var counterCompHint: String {
        let theirs = trade.compensationAmount
        let delta = counterComp - theirs
        if delta == 0 {
            return theirs > 0 ? "Same as their \(NumberFormat.currency(theirs)) offer" : "No compensation"
        }
        return delta > 0
            ? "\(NumberFormat.currency(delta)) more than they offered"
            : "\(NumberFormat.currency(-delta)) less than they offered"
    }

    private func openCounter() {
        errorText = nil
        showCounter = true
        counterComp = trade.compensationAmount
        // Build days once on tap — never inside body — so Counter stays snappy.
        let days = store.counterAlternateDays(for: trade)
        counterDays = days
        counterShift = days.first
        if days.isEmpty {
            showCounter = false
            errorText = "No other days available to counter with."
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func respond(accept: Bool) {
        guard !busy else { return }
        busy = true
        errorText = nil
        Task { @MainActor in
            do {
                let penalty = try await store.respondToTrade(trade, accept: accept)
                let fee = NSDecimalNumber(decimal: penalty).intValue
                let msg = accept
                    ? (fee > 0 ? "Accepted · \(NumberFormat.currency(fee)) fee" : "Trade accepted")
                    : "Trade declined"
                doneMessage = msg
                UINotificationFeedbackGenerator().notificationOccurred(accept ? .success : .warning)
                onMessage(accept ? "Trade accepted with \(fromName)" : "Trade declined")
            } catch {
                errorText = error.localizedDescription
                busy = false
            }
        }
    }

    private func sendCounter() {
        guard !busy, let alt = counterShift else { return }
        busy = true
        errorText = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task { @MainActor in
            do {
                _ = try await store.counterTrade(
                    original: trade,
                    newRequestedShift: alt,
                    compensationAmount: counterComp
                )
                doneMessage = "Counter sent"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onMessage("Counter sent · your \(alt.shift.displayDateLabel) for \(theirDay)")
            } catch {
                errorText = error.localizedDescription
                busy = false
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
    @State private var selectedPartnerShift: AssignedShiftsStore.AssignedShift?
    @State private var compensation: Double = 0
    @State private var errorMessage: String?
    @State private var didSend = false

    private var tradePreview: PolicyPreview { store.preview(for: .trade, assigned: assigned) }

    private var partnerDays: [AssignedShiftsStore.AssignedShift] {
        guard let doc = selectedDoctor else { return [] }
        return store.tradeableShifts(
            forPartner: doc.id,
            specialty: assigned.shift.specialty,
            excludingDate: assigned.shift.date
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ShiftRow(shift: assigned.shift).cardStyle()

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Trade Policy", systemImage: "doc.text")
                        if tradePreview.allowed {
                            if tradePreview.penaltyAmount > 0 {
                                Text("Fee if accepted: \(NumberFormat.currency(NSDecimalNumber(decimal: tradePreview.penaltyAmount).intValue)) (\(Int(tradePreview.penaltyPercent * 100))%)")
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
                                    selectedPartnerShift = nil
                                    store.preparePartnerTradeDays(
                                        forPartner: doc.id,
                                        specialty: assigned.shift.specialty,
                                        excludingDate: assigned.shift.date
                                    )
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

                    if selectedDoctor != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Their Day You Want", systemImage: "calendar")
                            TradePartnerCalendar(days: partnerDays, selected: $selectedPartnerShift)
                        }
                        .cardStyle()

                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Your Offer", systemImage: "dollarsign.circle")
                            HStack {
                                Text("Amount")
                                Spacer()
                                Text(NumberFormat.currency(compensation)).font(.headline).foregroundStyle(Color.accentColor)
                            }
                            Slider(value: $compensation, in: 0...1_000, step: 25)
                        }
                        .cardStyle()
                    }

                    if let err = errorMessage {
                        Text(err).font(.caption).foregroundStyle(.red).cardStyle()
                    }

                    Button { sendTrade() } label: {
                        Group {
                            if didSend { Label("Request Sent!", systemImage: "checkmark.circle.fill") }
                            else { Text("Send Trade Request") }
                        }
                        .font(.headline).frame(maxWidth: .infinity).padding()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selectedDoctor == nil || selectedPartnerShift == nil || !tradePreview.allowed || didSend)
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
        guard let doctor = selectedDoctor, let wanted = selectedPartnerShift else { return }
        Task {
            do {
                _ = try await store.requestTrade(
                    for: assigned,
                    toDoctor: doctor,
                    requestedShift: wanted,
                    compensationAmount: compensation
                )
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
                                Text("Cancellation penalty: \(NumberFormat.currency(penaltyInt))")
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
