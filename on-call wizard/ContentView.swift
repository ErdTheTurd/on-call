import SwiftUI
import Combine
import Charts

// MARK: - Root

struct IdentifiableDate: Identifiable {
    let id = UUID()
    let date: Date
}

struct ContentView: View {
    @StateObject private var auth = AuthService.shared

    var body: some View {
        ZStack {
            BackgroundGradient()
            switch auth.state {
            case .loggedOut:
                AuthView(auth: auth)
                    .transition(.opacity)
            case .needsOnboarding(let role):
                onboardingView(for: role)
                    .transition(.move(edge: .trailing))
            case .locked(let role):
                BiometricLockScreen(auth: auth, role: role)
                    .transition(.opacity)
            case .authenticated(let role):
                mainView(for: role)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: auth.state)
    }

    @ViewBuilder
    private func onboardingView(for role: UserRole) -> some View {
        switch role {
        case .doctor:
            DoctorOnboardingView { _ in auth.completeOnboarding(role: .doctor) }
        case .hospital:
            HospitalOnboardingView { _ in auth.completeOnboarding(role: .hospital) }
        }
    }

    @ViewBuilder
    private func mainView(for role: UserRole) -> some View {
        switch role {
        case .doctor:
            DoctorRootView(profile: DoctorProfile.load(), onSignOut: { auth.signOut() })
        case .hospital:
            HospitalRootView(profile: HospitalProfile.load(), onSignOut: { auth.signOut() })
        }
    }
}

// MARK: - Role Selection

struct RoleSelectionView: View {
    @ObservedObject private var auth = AuthService.shared

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "stethoscope.circle.fill")
                    .font(.system(size: 72)).symbolRenderingMode(.hierarchical).foregroundStyle(Color.accentColor)
                Text("On Call")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("Dynamic marketplace for on‑call coverage")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
            VStack(spacing: 12) {
                RoleButton(title: "I'm a Doctor",   subtitle: "Find and accept premium shifts",  systemImage: "person.fill.badge.plus") { auth.selectRole(.doctor) }
                RoleButton(title: "I'm a Hospital", subtitle: "Post shifts and manage coverage", systemImage: "cross.case.fill")         { auth.selectRole(.hospital) }
            }
            .padding(.horizontal, 24)
            Text("By continuing you agree to our Terms & Privacy Policy")
                .font(.footnote).foregroundStyle(.tertiary).multilineTextAlignment(.center).padding(.top, 20).padding(.bottom, 40)
        }
    }
}

struct RoleButton: View {
    let title: String; let subtitle: String; let systemImage: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack { Circle().fill(Color.accentColor).frame(width: 46, height: 46); Image(systemName: systemImage).font(.body.weight(.semibold)).foregroundStyle(.white) }
                VStack(alignment: .leading, spacing: 2) { Text(title).font(.headline); Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.secondary.opacity(0.5))
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Verification Badge

struct VerificationBadge: View {
    let status: VerificationStatus; var compact: Bool = false
    var color: Color { switch status { case .verified: return .green; case .pending: return .orange; case .flagged: return .red; default: return .secondary } }
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
            if !compact { Text(status.label).font(.caption.weight(.semibold)) }
        }
        .font(.caption).foregroundStyle(color)
        .padding(.horizontal, compact ? 6 : 8).padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Doctor Root

// MARK: - Doctor Preferences Store

final class DoctorPreferencesStore: ObservableObject {
    static let shared = DoctorPreferencesStore()
    private static let key = "doctor_prefs_v1"

    @Published var showOnlyMySpecialties: Bool = true { didSet { save() } }
    @Published var hiddenHospitalIDs: Set<UUID> = []  { didSet { save() } }
    @Published var hiddenSpecialties: Set<String> = [] { didSet { save() } }
    @Published var notifyNewShifts: Bool = true        { didSet { save() } }
    @Published var notifyTradeRequests: Bool = true    { didSet { save() } }
    @Published var notifyApprovals: Bool = true        { didSet { save() } }

    private init() { load() }

    /// Returns `true` when `shift` should be shown to the doctor with the given profile.
    func passes(shift: Shift, profile: DoctorProfile?) -> Bool {
        if hiddenHospitalIDs.contains(shift.hospitalID) { return false }
        if hiddenSpecialties.contains(shift.specialty)  { return false }
        if showOnlyMySpecialties, let specialties = profile?.specialties, !specialties.isEmpty {
            return specialties.contains(shift.specialty)
        }
        return true
    }

    // MARK: Persistence
    private struct Stored: Codable {
        var showOnlyMySpecialties: Bool
        var hiddenHospitalIDs: [UUID]
        var hiddenSpecialties: [String]
        var notifyNewShifts: Bool
        var notifyTradeRequests: Bool
        var notifyApprovals: Bool
    }

    private func save() {
        let s = Stored(showOnlyMySpecialties: showOnlyMySpecialties,
                       hiddenHospitalIDs: Array(hiddenHospitalIDs),
                       hiddenSpecialties: Array(hiddenSpecialties),
                       notifyNewShifts: notifyNewShifts,
                       notifyTradeRequests: notifyTradeRequests,
                       notifyApprovals: notifyApprovals)
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let s = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        showOnlyMySpecialties = s.showOnlyMySpecialties
        hiddenHospitalIDs = Set(s.hiddenHospitalIDs)
        hiddenSpecialties = Set(s.hiddenSpecialties)
        notifyNewShifts = s.notifyNewShifts
        notifyTradeRequests = s.notifyTradeRequests
        notifyApprovals = s.notifyApprovals
    }
}

// MARK: - Doctor Root View

struct DoctorRootView: View {
    let profile: DoctorProfile?
    var onSignOut: () -> Void
    @State private var showDashboard = false
    @StateObject private var tokens = TokenStore.shared
    @StateObject private var points = PointsStore.shared
    @StateObject private var assignments = AssignedShiftsStore.shared

    var body: some View {
        TabView {
            DoctorHomeView(profile: profile, showDashboard: $showDashboard)
                .tabItem { Label("Home", systemImage: "house.fill") }
            NavigationStack {
                MyAssignedShiftsView()
            }
            .tabItem { Label("My Shifts", systemImage: "arrow.triangle.2.circlepath") }
            .badge(assignments.pendingTradeCount > 0 ? assignments.pendingTradeCount : 0)
            CredentialsView(profile: profile)
                .tabItem { Label("Credentials", systemImage: "checkmark.seal.fill") }
        }
        .sheet(isPresented: $showDashboard) {
            DoctorDashboardView(profile: profile, onSignOut: onSignOut)
        }
    }
}

// MARK: - Doctor Dashboard (hamburger)

struct DoctorDashboardView: View {
    let profile: DoctorProfile?
    var onSignOut: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var points = PointsStore.shared
    @StateObject private var tokens = TokenStore.shared

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundGradient()
                List {
                    // Profile header
                    if let p = profile {
                        Section {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 60, height: 60)
                                    Text(String(p.firstName.prefix(1)) + String(p.lastName.prefix(1)))
                                        .font(.title.bold()).foregroundStyle(Color.accentColor)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(p.displayName).font(.headline)
                                    Text(p.specialties.first ?? "").font(.subheadline).foregroundStyle(.secondary)
                                    VerificationBadge(status: p.verificationStatus)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .listRowBackground(Color.clear)
                    }

                    // Points
                    Section("Rewards") {
                        NavigationLink {
                            ZStack { BackgroundGradient(); ScrollView { PointsCard(store: points).padding() } }
                                .navigationTitle("My Points")
                        } label: {
                            HStack {
                                Image(systemName: points.level.icon).foregroundStyle(Color.accentColor).frame(width: 28)
                                Text("Points & Level")
                                Spacer()
                                Text("\(points.totalPoints) pts").font(.subheadline.weight(.semibold)).foregroundStyle(Color.accentColor)
                            }
                        }
                    }

                    Section("Schedule") {
                        NavigationLink {
                            MyAssignedShiftsView()
                        } label: {
                            Label("My Shifts", systemImage: "calendar.badge.clock")
                        }
                        NavigationLink {
                            UpcomingScheduleView()
                        } label: {
                            Label("Requested Days", systemImage: "calendar.badge.plus")
                        }
                        NavigationLink {
                            EarningsHistoryView()
                        } label: {
                            Label("My Earnings", systemImage: "dollarsign.circle.fill")
                        }
                        NavigationLink {
                            ShiftHistoryView()
                        } label: {
                            Label("Shift History", systemImage: "clock.arrow.circlepath")
                        }
                    }

                    Section("Tokens") {
                        HStack {
                            Image(systemName: "ticket.fill").foregroundStyle(Color.accentColor).frame(width: 28)
                            Text("Daily Tokens")
                            Spacer()
                            TokenBadge(store: tokens)
                        }
                    }

                    Section("Account") {
                        NavigationLink {
                            MyInfoView(profile: profile)
                        } label: {
                            Label("My Info & Documents", systemImage: "person.text.rectangle.fill")
                        }
                        NavigationLink {
                            DoctorPreferencesView(profile: profile)
                        } label: {
                            Label("Preferences", systemImage: "slider.horizontal.3")
                        }
                        Button(role: .destructive) { dismiss(); onSignOut() } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Doctor Preferences View

struct DoctorPreferencesView: View {
    let profile: DoctorProfile?
    @ObservedObject private var prefs = DoctorPreferencesStore.shared
    @ObservedObject private var hospitalService = Services.hospital
    @ObservedObject private var assignments = AssignedShiftsStore.shared

    private var mySpecialties: [String] { profile?.specialties ?? [] }

    /// All hospitals visible to the doctor, deduped by ID, from both open shifts and assigned shifts.
    private var knownHospitals: [(id: UUID, name: String)] {
        var seen: [UUID: String] = [:]
        for shift in hospitalService.shifts { seen[shift.hospitalID] = shift.hospital }
        for assigned in assignments.activeAssignedShifts() { seen[assigned.shift.hospitalID] = assigned.shift.hospital }
        return seen.map { (id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    var body: some View {
        ZStack {
            BackgroundGradient()
            List {

                // MARK: Specialty
                Section {
                    Toggle(isOn: $prefs.showOnlyMySpecialties) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show only my specialties")
                                .font(.subheadline.weight(.medium))
                            Text("Hides shifts outside your registered specialties")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    if !prefs.showOnlyMySpecialties && !mySpecialties.isEmpty {
                        ForEach(mySpecialties, id: \.self) { sp in
                            let hidden = prefs.hiddenSpecialties.contains(sp)
                            Toggle(sp, isOn: Binding(
                                get: { !hidden },
                                set: { show in
                                    if show { prefs.hiddenSpecialties.remove(sp) }
                                    else     { prefs.hiddenSpecialties.insert(sp) }
                                }
                            ))
                        }
                    }
                } header: {
                    Label("My Specialties", systemImage: "stethoscope")
                } footer: {
                    if mySpecialties.isEmpty {
                        Text("No specialties on file — update your profile.")
                    } else if prefs.showOnlyMySpecialties {
                        Text("You are currently seeing: \(mySpecialties.joined(separator: ", "))")
                            .font(.caption)
                    }
                }

                // MARK: Hospitals
                Section {
                    if knownHospitals.isEmpty {
                        Label("No hospitals found yet", systemImage: "building.2")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        ForEach(knownHospitals, id: \.id) { h in
                            Toggle(isOn: Binding(
                                get: { !prefs.hiddenHospitalIDs.contains(h.id) },
                                set: { show in
                                    if show { prefs.hiddenHospitalIDs.remove(h.id) }
                                    else     { prefs.hiddenHospitalIDs.insert(h.id) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(h.name).font(.subheadline.weight(.medium))
                                    if prefs.hiddenHospitalIDs.contains(h.id) {
                                        Text("Hidden").font(.caption).foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Label("Hospitals", systemImage: "building.2.crop.circle")
                } footer: {
                    Text("Toggle off a hospital to hide its open shifts from your home view.")
                }

                // MARK: Notifications
                Section {
                    Toggle(isOn: $prefs.notifyNewShifts) {
                        Label("New matching shifts", systemImage: "bell.badge")
                    }
                    Toggle(isOn: $prefs.notifyTradeRequests) {
                        Label("Incoming trade requests", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Toggle(isOn: $prefs.notifyApprovals) {
                        Label("Approvals & status updates", systemImage: "checkmark.circle")
                    }
                } header: {
                    Label("Notifications", systemImage: "bell")
                }

                // MARK: About
                Section {
                    HStack {
                        Text("Specialties on file")
                        Spacer()
                        Text(mySpecialties.isEmpty ? "None" : mySpecialties.joined(separator: ", "))
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    if let cred = profile?.credential {
                        HStack {
                            Text("Credential")
                            Spacer()
                            Text(cred.rawValue).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Label("Profile Summary", systemImage: "person.crop.circle")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - My Info View

struct MyInfoView: View {
    let profile: DoctorProfile?
    @StateObject private var docStore = DocumentUploadService.shared

    var body: some View {
        ZStack {
            BackgroundGradient()
            ScrollView {
                VStack(spacing: 14) {
                    if let p = profile {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Identity")
                            CredRow(icon: "person.fill",    label: "Name",    value: p.displayName)
                            Divider()
                            CredRow(icon: "number",         label: "NPI",     value: p.npi)
                            Divider()
                            CredRow(icon: "doc.text.fill",  label: "License", value: "\(p.licenseNumber) · \(p.licenseState)")
                            Divider()
                            CredRow(icon: "envelope.fill",  label: "Email",   value: p.email)
                        }
                        .cardStyle()
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Verification Documents", systemImage: "doc.badge.plus")
                        Text("Upload your state license, DEA certificate, malpractice COI, and board certification.")
                            .font(.caption).foregroundStyle(.secondary)

                        if docStore.uploadedDocuments.isEmpty {
                            DocumentPickerButton(label: "State License") { name in
                                docStore.registerUpload(fileName: name)
                            }
                        } else {
                            ForEach(docStore.uploadedDocuments) { doc in
                                HStack {
                                    Image(systemName: "doc.fill").foregroundStyle(Color.accentColor)
                                    Text(doc.fileName).font(.subheadline)
                                    Spacer()
                                    Text(doc.reviewStatus.rawValue.capitalized)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            DocumentPickerButton(label: "Additional Document") { name in
                                docStore.registerUpload(fileName: name)
                            }
                        }
                    }
                    .cardStyle()
                }
                .padding()
            }
        }
        .navigationTitle("My Info")
    }
}

// MARK: - Upcoming Schedule

struct UpcomingScheduleView: View {
    @StateObject private var tokens = TokenStore.shared

    var upcoming: [TokenStore.TokenRequest] {
        tokens.requestedDays
            .filter { $0.date >= Calendar.current.startOfDay(for: Date()) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        ZStack {
            BackgroundGradient()
            ScrollView {
                VStack(spacing: 10) {
                    if upcoming.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar.badge.plus").font(.system(size: 44)).foregroundStyle(.secondary)
                            Text("No upcoming schedule").font(.headline).foregroundStyle(.secondary)
                            Text("Tap days on the calendar to request call.").font(.subheadline).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity).padding(40)
                    } else {
                        ForEach(upcoming) { req in
                            HStack(spacing: 14) {
                                VStack(spacing: 2) {
                                    Text(req.date.formatted(.dateTime.month(.abbreviated))).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                                    Text(req.date.formatted(.dateTime.day())).font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(Color.accentColor)
                                }
                                .frame(width: 44)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(req.hospitalName).font(.headline)
                                    Text(req.specialty).font(.subheadline).foregroundStyle(.secondary)
                                    Text(req.requestedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.tertiary)
                                }
                                Spacer()
                                StatusBadge(label: req.statusLabel, color: statusColor(req.status))
                            }
                            .cardStyle()
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Schedule")
    }

    private func statusColor(_ s: TokenStore.TokenRequest.RequestStatus) -> Color {
        switch s {
        case .pending: return .orange; case .approved, .autoApproved: return .green; case .denied: return .red
        }
    }
}

private struct StatusBadge: View {
    let label: String; let color: Color
    var body: some View {
        Text(label).font(.caption2.weight(.bold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4).background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Earnings History

struct EarningsHistoryView: View {
    @StateObject private var assignments = AssignedShiftsStore.shared

    private var completed: [AssignedShiftsStore.AssignedShift] { assignments.completedShifts() }
    private var totalEarned: Double { assignments.totalEarnings() }

    var body: some View {
        ZStack {
            BackgroundGradient()
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "This Month")
                        if completed.isEmpty && assignments.activeAssignedShifts().isEmpty {
                            Text("No earnings yet — accept shifts after hospital approval.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 20) {
                                StatPill(label: "Earned", value: "$\(Int(totalEarned))")
                                StatPill(label: "Shifts", value: "\(completed.count + assignments.activeAssignedShifts().count)")
                                StatPill(label: "Avg/shift", value: completed.isEmpty ? "—" : "$\(Int(totalEarned / Double(max(1, completed.count))))")
                            }
                        }
                    }
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(title: "Recent Shifts")
                            .padding(.bottom, 10)
                        if completed.isEmpty {
                            Text("Completed shifts will appear here.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(Array(completed.prefix(5).enumerated()), id: \.element.id) { i, assigned in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(assigned.shift.hospital).font(.headline)
                                        Text(assigned.shift.displayDateLabel).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("$\(Int(assigned.shift.totalEarnings))").font(.headline).foregroundStyle(Color.accentColor)
                                }
                                .padding(.vertical, 6)
                                if i < min(4, completed.count - 1) { Divider() }
                            }
                        }
                    }
                    .cardStyle()
                }
                .padding()
            }
        }
        .navigationTitle("Earnings")
    }
}

private struct StatPill: View {
    let label: String; let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(Color.accentColor)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

// MARK: - Shift History

struct ShiftHistoryView: View {
    @StateObject private var assignments = AssignedShiftsStore.shared

    var body: some View {
        ZStack {
            BackgroundGradient()
            ScrollView {
                VStack(spacing: 10) {
                    if assignments.completedShifts().isEmpty {
                        Text("No completed shifts yet.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 32).cardStyle()
                    } else {
                        ForEach(assignments.completedShifts()) { assigned in
                            ShiftRow(shift: assigned.shift).cardStyle()
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("History")
    }
}

// MARK: - Doctor Home

struct DoctorHomeView: View {
    let profile: DoctorProfile?
    @Binding var showDashboard: Bool
    @State private var selectedDate: Date? = nil
    @State private var calendarMonth: Date = Date()
    @State private var shiftDaySheet: IdentifiableDate? = nil
    @StateObject private var tokens = TokenStore.shared
    @StateObject private var points = PointsStore.shared
    @StateObject private var assignments = AssignedShiftsStore.shared
    @StateObject private var unavailable = UnavailableDaysStore.shared
    @ObservedObject private var hospitalService = Services.hospital
    @ObservedObject private var prefs = DoctorPreferencesStore.shared

    private var allShifts: [Shift] {
        hospitalService.shifts
            .filter { !$0.isPast && !assignments.isShiftFilled($0.id) }
            .filter { prefs.passes(shift: $0, profile: profile) }
    }

    private var dayData: [CalendarHeatmap.DayData] {
        DemoData.doctorCalendarData(
            for: calendarMonth,
            shifts: allShifts,
            assignments: assignments,
            unavailable: unavailable,
            currentDoctorID: assignments.currentDoctorID
        )
    }

    private func dayInfo(for date: Date) -> CalendarHeatmap.DayData? {
        dayData.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    private var shiftsForSelectedDate: [Shift] {
        guard let date = selectedDate else { return [] }
        return allShifts.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundGradient()
                ScrollView {
                    VStack(spacing: Brand.sectionSpacing) {
                        // Verification warning
                        if let p = profile, p.verificationStatus != .verified {
                            PendingVerificationBanner(status: p.verificationStatus, flags: p.verificationFlags)
                        }

                        // Points card
                        PointsCard(store: points)

                        // Token badge
                        HStack {
                            TokenBadge(store: tokens)
                            Spacer()
                            Text("Tap a day to request call").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 2)

                        // Calendar
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Button { calendarMonth = Calendar.current.date(byAdding: .month, value: -1, to: calendarMonth) ?? calendarMonth } label: {
                                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.white.opacity(0.5))
                                }.buttonStyle(.plain)
                                Spacer()
                                Button { calendarMonth = Calendar.current.date(byAdding: .month, value: 1, to: calendarMonth) ?? calendarMonth } label: {
                                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.white.opacity(0.5))
                                }.buttonStyle(.plain)
                            }
                            .padding(.bottom, 4)
                            CalendarHeatmap(month: calendarMonth, dayData: dayData, mode: .doctor, embedded: true) { date in
                                guard let info = dayInfo(for: date),
                                      !info.isFilledByOthers,
                                      !info.isHospitalUnavailable else { return }
                                selectedDate = date
                                shiftDaySheet = IdentifiableDate(date: date)
                            }

                            CalendarDayLegend()
                                .padding(.top, 8)
                            if let date = selectedDate {
                                Divider().padding(.top, 12)
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(date.formatted(.dateTime.weekday(.wide).month().day()))
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 10)
                                    if shiftsForSelectedDate.isEmpty {
                                        HStack { Image(systemName: "moon.zzz").foregroundStyle(.secondary); Text("No open shifts").foregroundStyle(Color.white.opacity(0.4)) }
                                            .font(.subheadline).padding(.vertical, 6)
                                    } else {
                                        ForEach(shiftsForSelectedDate) { shift in
                                            ShiftRow(shift: shift)
                                            if shift != shiftsForSelectedDate.last { Divider() }
                                        }
                                    }
                                }
                            }
                        }
                        .cardStyle()

                        UpcomingShiftHighlights()
                        CredentialStatusCard(profile: profile)
                    }
                    .padding()
                }
            }
            .navigationTitle(profile.map { "Dr. \($0.lastName)" } ?? "On‑Call")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDashboard = true } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.primary)
                    }
                }
            }
        }
        .sheet(item: $shiftDaySheet) { wrapper in
            DayShiftApplySheet(
                date: wrapper.date,
                shifts: allShifts.filter {
                    Calendar.current.isDate($0.date, inSameDayAs: wrapper.date) && !$0.isPast
                },
                profile: profile
            )
        }
        .onAppear {
            if hospitalService.shifts.isEmpty, let hp = HospitalProfile.load() {
                hospitalService.ensureDailyShifts(from: Date(), days: 120, hospitalID: hp.id, hospitalName: hp.name)
            }
        }
    }
}

// MARK: - Day Shift Apply Sheet

struct DayShiftApplySheet: View {
    let date: Date
    let shifts: [Shift]
    let profile: DoctorProfile?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var tokens = TokenStore.shared
    @StateObject private var points = PointsStore.shared
    @State private var applied: Set<UUID> = []
    @State private var tokenError: String? = nil

    var holiday: HolidayCalendar.Holiday? { HolidayCalendar.holiday(on: date) }

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundGradient()
                ScrollView {
                    VStack(spacing: 14) {
                        // Date header
                        VStack(spacing: 6) {
                            Text(date.formatted(.dateTime.weekday(.wide)))
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(date.formatted(.dateTime.month(.wide).day().year()))
                                .font(.system(.title2, design: .rounded, weight: .bold))
                            if let h = holiday {
                                Label("\(h.name) — +\(Int(h.premium * 100))% premium", systemImage: "star.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.12), in: Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity).cardStyle()

                        // Token status
                        HStack {
                            TokenBadge(store: tokens)
                            Spacer()
                            if let err = tokenError {
                                Text(err).font(.caption).foregroundStyle(.red)
                            }
                        }

                        // Existing request for this day
                        if let req = tokens.requestStatus(for: date, doctorID: profile?.id) {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar.badge.checkmark").foregroundStyle(.green).font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Request submitted").font(.headline)
                                    Text(req.statusLabel).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Cancel") { tokens.cancelRequest(id: req.id) }
                                    .font(.subheadline).foregroundStyle(.red)
                            }
                            .cardStyle()
                        }

                        // Shifts
                        if shifts.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "moon.zzz").font(.system(size: 36)).foregroundStyle(.secondary)
                                Text("No open shifts on this day").foregroundStyle(Color.white.opacity(0.4))
                                Text("You can still request call — the hospital may post shifts later.")
                                    .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).padding(32).cardStyle()

                            // Request anyway button
                            if tokens.requestStatus(for: date, doctorID: profile?.id) == nil {
                                Button {
                                    let hid = shifts.first?.hospitalID ?? HospitalProfile.load()?.id ?? UUID()
                                    requestDay(hospital: shifts.first?.hospital ?? HospitalProfile.load()?.name ?? "Hospital", specialty: profile?.specialties.first ?? "Internal Medicine", hospitalID: hid)
                                } label: {
                                    Label("Request This Day", systemImage: "calendar.badge.plus")
                                        .font(.headline).frame(maxWidth: .infinity).padding()
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(tokens.tokensRemaining == 0)
                            }
                        } else {
                            ForEach(shifts) { shift in
                                VStack(alignment: .leading, spacing: 12) {
                                    ShiftRow(shift: shift)
                                    Divider()
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Est. earnings").font(.caption).foregroundStyle(.secondary)
                                            let premium = HolidayCalendar.premiumMultiplier(on: date)
                                            let adjusted = shift.totalEarnings * premium
                                            Text("$\(Int(adjusted))")
                                                .font(.title3.bold()).foregroundStyle(Color.accentColor)
                                            if premium > 1.0 {
                                                Text("Includes \(Int((premium - 1) * 100))% holiday premium")
                                                    .font(.caption2).foregroundStyle(.orange)
                                            }
                                        }
                                        Spacer()
                                        if applied.contains(shift.id) {
                                            Label("Applied!", systemImage: "checkmark.circle.fill")
                                                .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                                        } else if tokens.requestStatus(for: date) != nil {
                                            Text("Day requested").font(.caption).foregroundStyle(.secondary)
                                        } else {
                                            Button {
                                                applyToShift(shift)
                                            } label: {
                                                Text("Apply")
                                                    .font(.headline).padding(.horizontal, 20).padding(.vertical, 10)
                                            }
                                            .buttonStyle(PrimaryButtonStyle())
                                            .disabled(tokens.tokensRemaining == 0)
                                        }
                                    }
                                }
                                .cardStyle()
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Available Shifts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private func applyToShift(_ shift: Shift) {
        let success = requestDay(hospital: shift.hospital, specialty: shift.specialty, hospitalID: shift.hospitalID, shiftRate: shift.currentRate)
        if success {
            applied.insert(shift.id)
            points.award(.shiftAccepted)
        }
    }

    @discardableResult
    private func requestDay(hospital: String, specialty: String, hospitalID: UUID, shiftRate: Double? = nil) -> Bool {
        guard let profile else {
            tokenError = "Complete your profile first."
            return false
        }
        let success = tokens.requestDay(
            date: date, hospitalID: hospitalID, hospital: hospital,
            specialty: specialty, doctor: profile, shiftRate: shiftRate
        )
        if !success {
            tokenError = tokens.tokensRemaining == 0 ? "No tokens remaining today." : "Already requested this day."
        }
        return success
    }
}

// MARK: - Upcoming Highlights

struct UpcomingShiftHighlights: View {
    @ObservedObject private var hospitalService = Services.hospital
    @StateObject private var assignments = AssignedShiftsStore.shared

    private var recommended: [Shift] {
        Array(hospitalService.shifts
            .filter { !$0.isPast && !assignments.isShiftFilled($0.id) }
            .sorted { $0.hoursUntilStart < $1.hoursUntilStart }
            .prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Recommended", systemImage: "sparkles")
            if recommended.isEmpty {
                Text("No open shifts right now. Check back after hospitals post coverage.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(recommended) { shift in
                    ShiftRow(shift: shift)
                    if shift.id != recommended.last?.id { Divider() }
                }
            }
        }
        .cardStyle()
    }
}

// MARK: - Credential Status Card

struct CredentialStatusCard: View {
    let profile: DoctorProfile?
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: profile?.verificationStatus == .verified ? "checkmark.seal.fill" : "clock.badge")
                .font(.title2)
                .foregroundStyle(profile?.verificationStatus == .verified ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(profile?.verificationStatus == .verified ? "Credentials Current" : "Verification In Progress")
                    .font(.headline)
                Text(profile?.verificationStatus.label ?? "Complete onboarding to verify")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if let p = profile { VerificationBadge(status: p.verificationStatus, compact: true) }
        }
        .cardStyle()
    }
}

// MARK: - Pending Verification Banner

struct PendingVerificationBanner: View {
    let status: VerificationStatus; let flags: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: status.systemImage)
                    .foregroundStyle(status == .pending ? Color.orange : Color.red).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status == .pending ? "Account Under Review" : "Verification Issue").font(.headline)
                    Text(status == .pending
                         ? "Browse shifts freely. You can't accept until our team approves your credentials."
                         : "There was an issue with your verification. Contact support.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !flags.isEmpty && status == .flagged {
                Divider()
                ForEach(flags, id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .cardStyle()
        .overlay(RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
            .strokeBorder((status == .pending ? Color.orange : Color.red).opacity(0.4), lineWidth: 1))
    }
}

// MARK: - Shifts Browse

struct ShiftsBrowseView: View {
    @State private var selectedShift: Shift? = nil
    @State private var searchText = ""
    @ObservedObject private var hospitalService = Services.hospital
    @StateObject private var assignments = AssignedShiftsStore.shared

    var filtered: [Shift] {
        let open = hospitalService.shifts.filter { !$0.isPast && !assignments.isShiftFilled($0.id) }
        guard !searchText.isEmpty else { return open }
        return open.filter {
            $0.specialty.localizedCaseInsensitiveContains(searchText) || $0.hospital.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundGradient()
                ScrollView {
                    VStack(spacing: 10) {
                        if filtered.isEmpty {
                            Text("No open shifts available.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 32).cardStyle()
                        } else {
                            ForEach(filtered) { shift in
                                Button { selectedShift = shift } label: { ShiftRow(shift: shift).cardStyle() }.buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Shifts")
            .searchable(text: $searchText, prompt: "Specialty or hospital")
            .sheet(item: $selectedShift) { ShiftDetailView(shift: $0) }
        }
    }
}

// MARK: - Shift Row

struct ShiftRow: View {
    let shift: Shift
    var showLockBadge: Bool = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(urgencyColor.opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: urgencyIcon).foregroundStyle(urgencyColor).font(.body.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(shift.hospital).font(.headline).lineLimit(1)
                Text("\(shift.specialty) · \(shift.durationLabel)").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Label("$\(Int(shift.currentRate))\(shift.rateUnitLabel)", systemImage: "dollarsign.circle.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(urgencyColor)
                    if showLockBadge {
                        Label("Rate locked", systemImage: "lock.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    urgencyBadge
                    Spacer()
                    Text(shift.displayDateLabel)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var urgencyColor: Color {
        switch shift.urgencyTier {
        case .critical: return .red; case .high: return .orange
        case .moderate: return Color(hue: 0.13, saturation: 0.9, brightness: 0.9)
        case .low: return .green; case .past: return .secondary
        }
    }
    private var urgencyIcon: String {
        switch shift.urgencyTier {
        case .critical: return "bolt.fill"; case .high: return "flame.fill"
        case .moderate: return "clock.fill"; case .low: return "cross.case.fill"; case .past: return "clock.badge.xmark"
        }
    }
    @ViewBuilder private var urgencyBadge: some View {
        switch shift.urgencyTier {
        case .critical:
            Text("URGENT").font(.caption2.weight(.heavy)).foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 2).background(Color.red, in: Capsule())
        case .high:
            Text("HIGH PAY").font(.caption2.weight(.bold)).foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 2).background(Color.orange, in: Capsule())
        default: EmptyView()
        }
    }
}

// MARK: - Shift Detail

struct ShiftDetailView: View {
    let shift: Shift
    @Environment(\.dismiss) private var dismiss
    @StateObject private var points = PointsStore.shared
    @State private var isAccepting = false; @State private var didAccept = false; @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundGradient()
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(shift.hospital).font(.title2.bold())
                            Text(shift.specialty).font(.headline).foregroundStyle(.secondary)
                            Text("\(shift.displayDateLabel) · \(shift.durationLabel)")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let h = HolidayCalendar.holiday(on: shift.date) {
                                Label("\(h.name) — +\(Int(h.premium * 100))% premium", systemImage: "star.fill")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).cardStyle()

                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(title: "Compensation", systemImage: "dollarsign.circle")
                            DetailRow(label: "Current rate", value: "$\(Int(shift.currentRate))\(shift.rateUnitLabel)", highlight: true)
                            Divider()
                            DetailRow(label: "Rate floor", value: "$\(Int(shift.rateFloor))\(shift.rateUnitLabel)")
                            Divider()
                            switch shift.escalationMode {
                            case .automatic:
                                DetailRow(label: "Rate type", value: "Auto-escalating")
                                Divider()
                                if shift.granularity == .day {
                                    DetailRow(label: "Days away", value: shift.daysUntilStart < 1 ? "< 1 day" : "\(Int(shift.daysUntilStart))d")
                                } else {
                                    DetailRow(label: "Time away", value: shift.hoursUntilStart < 1 ? "< 1 hour" : "\(Int(shift.hoursUntilStart))h")
                                }
                            case .flat(let r):
                                DetailRow(label: "Rate type", value: "Fixed — $\(Int(r))\(shift.rateUnitLabel)")
                            }
                            Divider()
                            DetailRow(label: "Est. total", value: "$\(Int(shift.totalEarnings))", highlight: true)
                        }
                        .cardStyle()

                        if case .automatic = shift.escalationMode {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(title: "Rate Schedule", systemImage: "chart.line.uptrend.xyaxis")
                                if shift.granularity == .day {
                                    ForEach([("30d+",shift.rateFloor*1.00),("14d",shift.rateFloor*1.10),("7d",shift.rateFloor*1.20),("3d",shift.rateFloor*1.35),("1d",shift.rateFloor*1.60),("Same day",shift.rateFloor*2.00)], id: \.0) { label, rate in
                                        HStack {
                                            Text(label).foregroundStyle(.secondary).font(.subheadline)
                                            Spacer()
                                            Text("$\(Int(rate))/day").font(.subheadline.weight(.semibold))
                                                .foregroundStyle(rate > shift.rateFloor * 1.5 ? Color.red : Color.accentColor)
                                        }
                                    }
                                } else {
                                    ForEach([("72h+",shift.rateFloor*1.00),("48h",shift.rateFloor*1.15),("24h",shift.rateFloor*1.35),("12h",shift.rateFloor*1.60),("6h",shift.rateFloor*1.85),("<2h",shift.rateFloor*2.20)], id: \.0) { label, rate in
                                        HStack {
                                            Text(label).foregroundStyle(.secondary).font(.subheadline)
                                            Spacer()
                                            Text("$\(Int(rate))/hr").font(.subheadline.weight(.semibold))
                                                .foregroundStyle(rate > shift.rateFloor * 1.5 ? Color.red : Color.accentColor)
                                        }
                                    }
                                }
                            }
                            .cardStyle()
                        }

                        if let err = errorMessage { Text(err).font(.subheadline).foregroundStyle(.red).cardStyle() }

                        Button { acceptShift() } label: {
                            Group {
                                if isAccepting { ProgressView().tint(.white) }
                                else if didAccept { Label("Accepted!", systemImage: "checkmark.circle.fill") }
                                else { Text("Accept Shift") }
                            }
                            .font(.headline).frame(maxWidth: .infinity).padding()
                        }
                        .buttonStyle(PrimaryButtonStyle()).disabled(isAccepting || didAccept)
                    }
                    .padding()
                }
            }
            .navigationTitle("Shift Details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
        }
    }

    @StateObject private var assignedStore = AssignedShiftsStore.shared
    @StateObject private var tokens = TokenStore.shared

    private func acceptShift() {
        isAccepting = true; errorMessage = nil
        Task {
            do {
                let doctorID = SessionStore.shared.currentDoctorID
                guard tokens.canAcceptShift(on: shift.date, hospitalID: shift.hospitalID, doctorID: doctorID) else {
                    throw TradeError.tokenNotApproved
                }
                try await Services.doctor.accept(shift: shift)
                await assignedStore.assign(shift, doctorID: doctorID)
                if SupabaseConfig.isConfigured {
                    _ = try? await SupabaseHTTPClient.shared.invokeFunction(
                        name: "accept-shift",
                        body: [
                            "shift_id": shift.id.uuidString,
                            "doctor_id": doctorID.uuidString,
                            "hospital_id": shift.hospitalID.uuidString,
                            "shift_date": ISO8601DateFormatter().string(from: shift.date.onlyDate())
                        ],
                        accessToken: SupabaseAuthService.shared.accessToken
                    )
                }
                await MainActor.run {
                    isAccepting = false; didAccept = true
                    points.award(.shiftAccepted)
                    if shift.granularity == .day ? shift.daysUntilStart < 1 : shift.hoursUntilStart < 2 {
                        points.award(.fastResponse)
                    }
                }
                try await Task.sleep(nanoseconds: 900_000_000)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    isAccepting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct DetailRow: View {
    let label: String; let value: String; var highlight: Bool = false
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(highlight ? .headline : .body).foregroundStyle(highlight ? Color.accentColor : Color.primary)
        }.font(Brand.brandFont)
    }
}

// MARK: - Credentials

struct CredentialsView: View {
    let profile: DoctorProfile?
    @StateObject private var docStore = DocumentUploadService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundGradient()
                ScrollView {
                    VStack(spacing: 14) {
                        if let p = profile {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { SectionHeader(title: "Identity"); Spacer(); VerificationBadge(status: p.verificationStatus) }
                                CredRow(icon: "person.fill",   label: "Name",    value: p.displayName)
                                Divider()
                                CredRow(icon: "number",        label: "NPI",     value: p.npi)
                                Divider()
                                CredRow(icon: "doc.text.fill", label: "License", value: "\(p.licenseNumber) · \(p.licenseState)")
                                Divider()
                                CredRow(icon: "envelope.fill", label: "Email",   value: p.email)
                            }
                            .cardStyle()

                            if !p.specialties.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionHeader(title: "Specialties")
                                    FlowLayout(tags: p.specialties)
                                }
                                .cardStyle()
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: "Documents")
                            if docStore.uploadedDocuments.isEmpty {
                                Text("No documents uploaded yet. Add them from My Info.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            } else {
                                ForEach(docStore.uploadedDocuments) { doc in
                                    CredRow(icon: "doc.fill", label: doc.fileName, value: doc.reviewStatus.rawValue.capitalized, valueColor: doc.reviewStatus == .approved ? .green : .orange)
                                    if doc.id != docStore.uploadedDocuments.last?.id { Divider() }
                                }
                            }
                        }
                        .cardStyle()
                    }
                    .padding()
                }
            }
            .navigationTitle("Credentials")
        }
    }
}

private struct CredRow: View {
    let icon: String; let label: String; let value: String; var valueColor: Color = .primary
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(Color.accentColor).frame(width: 22)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(valueColor).font(.subheadline.weight(.medium))
        }.font(Brand.brandFont)
    }
}

private struct FlowLayout: View {
    let tags: [String]
    var body: some View {
        var rows: [[String]] = [[]]
        var rowWidth: CGFloat = 0
        for tag in tags {
            let w = CGFloat(tag.count * 9 + 24)
            if rowWidth + w > 280 { rows.append([]); rowWidth = 0 }
            rows[rows.count - 1].append(tag); rowWidth += w + 8
        }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    ForEach(rows[i], id: \.self) { tag in
                        Text(tag).font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12), in: Capsule()).foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
    }
}

// MARK: - Hospital Root

struct HospitalRootView: View {
    let profile: HospitalProfile?
    var onSignOut: () -> Void
    @State private var showDashboard = false
    @State private var selectedTab = 0
    @StateObject private var rosterStore = DoctorRosterStore.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            HospitalDashboardView(profile: profile, showDashboard: $showDashboard, selectedTab: $selectedTab)
                .tabItem { Label("Dashboard", systemImage: "rectangle.grid.2x2.fill") }
                .tag(0)
            AlterShiftsView(profile: profile)
                .tabItem { Label("Alter Shifts", systemImage: "calendar.badge.clock") }
                .tag(1)
            CandidatesView()
                .environmentObject(rosterStore)
                .tabItem { Label("Doctors", systemImage: "person.3.fill") }
                .tag(2)
        }
        .onAppear {
            if let profile {
                policyBootstrap(profile)
                if Services.hospital.shifts.filter({ $0.hospitalID == profile.id }).isEmpty {
                    Services.hospital.ensureDailyShifts(from: Date(), days: 120, hospitalID: profile.id, hospitalName: profile.name, policy: profile.schedulingPolicy)
                }
            }
        }
        .sheet(isPresented: $showDashboard) {
            HospitalDashboardSheet(profile: profile, selectedTab: $selectedTab, onSignOut: onSignOut)
        }
    }

    private func policyBootstrap(_ profile: HospitalProfile) {
        SchedulingPolicyStore.shared.loadForHospital(profile)
    }
}

// MARK: - Hospital Dashboard Sheet

struct HospitalDashboardSheet: View {
    let profile: HospitalProfile?
    @Binding var selectedTab: Int
    var onSignOut: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hospital_priority_posting") private var priorityPosting = false
    @AppStorage("hospital_auto_pay") private var autoPayInvoices = false

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundGradient()
                List {
                    if let p = profile {
                        Section {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.15)).frame(width: 56, height: 56)
                                    Image(systemName: "building.2.fill").font(.title2).foregroundStyle(Color.accentColor)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(p.name).font(.headline)
                                    Text("NPI: \(p.npi)").font(.subheadline).foregroundStyle(.secondary)
                                    VerificationBadge(status: p.verificationStatus)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .listRowBackground(Color.clear)
                    }
                    Section("Management") {
                        NavigationLink {
                            HospitalOpenShiftsView(profile: profile)
                        } label: {
                            Label("Open Shifts", systemImage: "clock.badge.exclamationmark")
                        }
                        NavigationLink {
                            HospitalAnalyticsView(profile: profile)
                        } label: {
                            Label("Analytics", systemImage: "chart.bar.fill")
                        }
                        NavigationLink {
                            HospitalBillingView(profile: profile)
                        } label: {
                            Label("Billing", systemImage: "creditcard.fill")
                        }
                        NavigationLink {
                            HospitalPolicySettingsView(hospitalProfile: profile)
                        } label: {
                            Label("On Call", systemImage: "slider.horizontal.3")
                        }
                    }
                    Section("Account") {
                        Toggle("Priority Posting", isOn: $priorityPosting)
                        Toggle("Auto-pay Invoices", isOn: $autoPayInvoices)
                        Button(role: .destructive) { dismiss(); onSignOut() } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Hospital Main Dashboard

struct HospitalDashboardView: View {
    let profile: HospitalProfile?
    @Binding var showDashboard: Bool
    @Binding var selectedTab: Int
    @StateObject private var unavailable = UnavailableDaysStore.shared
    @StateObject private var tokens = TokenStore.shared
    @ObservedObject private var hospitalService = Services.hospital
    @StateObject private var roster = DoctorRosterStore.shared
    @State private var calendarMonth = Date()
    @State private var hoverDate: Date?
    @State private var detailDate: IdentifiableDate?

    private var hospitalID: UUID? { profile?.id }

    private var dayData: [CalendarHeatmap.DayData] {
        guard let hospitalID else { return [] }
        return HospitalDayInsights.calendarDayData(for: calendarMonth, hospitalID: hospitalID)
    }

    private var hoverSummary: HospitalDaySummary? {
        guard let hospitalID, let hoverDate else { return nil }
        return HospitalDayInsights.summary(for: hoverDate, hospitalID: hospitalID)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundGradient()
                ScrollView {
                    VStack(spacing: Brand.sectionSpacing) {
                        if let p = profile, p.verificationStatus != .verified {
                            PendingVerificationBanner(status: p.verificationStatus, flags: p.verificationFlags)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Button { calendarMonth = Calendar.current.date(byAdding: .month, value: -1, to: calendarMonth) ?? calendarMonth } label: {
                                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.white.opacity(0.5))
                                }.buttonStyle(.plain)
                                Spacer()
                                Text("Long press for coverage · Tap for details")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Spacer()
                                Button { calendarMonth = Calendar.current.date(byAdding: .month, value: 1, to: calendarMonth) ?? calendarMonth } label: {
                                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.white.opacity(0.5))
                                }.buttonStyle(.plain)
                            }

                            if let hoverSummary {
                                HospitalDayHoverCard(summary: hoverSummary)
                                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
                            }

                            CalendarHeatmap(
                                month: calendarMonth,
                                dayData: dayData,
                                mode: .hospital,
                                embedded: true,
                                hoverDate: $hoverDate
                            ) { date in
                                hoverDate = nil
                                detailDate = IdentifiableDate(date: date)
                            }
                            CalendarDayLegend(showHospitalHint: true)
                        }
                        .cardStyle()
                        .animation(.easeOut(duration: 0.2), value: hoverDate)

                        HStack(spacing: 12) {
                            Button { selectedTab = 1 } label: {
                                StatBadge(value: "\(hospitalService.openShiftCount)", label: "Open\nShifts")
                            }.buttonStyle(.plain)
                            Button { showDashboard = true } label: {
                                StatBadge(value: "\(hospitalService.fillRatePercent)%", label: "Fill Rate\n30 days")
                            }.buttonStyle(.plain)
                            Button { selectedTab = 2 } label: {
                                StatBadge(value: "\(roster.doctors.filter(\.isAutoApproved).count)", label: "Auto‑Approved\nDoctors")
                            }.buttonStyle(.plain)
                        }
                        .cardStyle()
                    }
                    .padding()
                }
            }
            .navigationTitle(profile?.name ?? "Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showDashboard = true } label: {
                        Image(systemName: "line.3.horizontal").font(.title3.weight(.semibold))
                    }
                }
            }
            .sheet(item: $detailDate) { wrapper in
                if let hospitalID {
                    HospitalDayDetailSheet(date: wrapper.date, hospitalID: hospitalID)
                }
            }
        }
    }
}

private struct StatBadge: View {
    let value: String; let label: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(Color.accentColor)
            Text(label).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Schedule Admin (spreadsheet view)

struct ScheduleAdminView: View {
    let profile: HospitalProfile?
    @StateObject private var tokens = TokenStore.shared

    @State private var filterStatus: AdminRow.RowStatus? = nil
    @State private var searchText = ""

    private var rows: [AdminRow] {
        guard let hospitalID = profile?.id else { return [] }
        return tokens.pendingRequests(forHospitalID: hospitalID).map { AdminRow(request: $0) }
    }

    var filtered: [AdminRow] {
        rows.filter { row in
            let matchSearch = searchText.isEmpty ||
                row.doctorName.localizedCaseInsensitiveContains(searchText) ||
                row.specialty.localizedCaseInsensitiveContains(searchText)
            let matchStatus = filterStatus == nil || row.status == filterStatus
            return matchSearch && matchStatus
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundGradient()
                ScrollView {
                    VStack(spacing: 12) {
                        if profile == nil {
                            Text("Complete hospital onboarding to review requests.")
                                .font(.subheadline).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 32)
                        } else {
                        HStack(spacing: 8) {
                            ScheduleSummaryPill(
                                value: "\(rows.filter { $0.status == .pending }.count)",
                                label: "Pending", color: Brand.warning,
                                isSelected: filterStatus == .pending
                            ) { filterStatus = filterStatus == .pending ? nil : .pending }
                            ScheduleSummaryPill(
                                value: "\(rows.filter { $0.status == .approved || $0.status == .autoApproved }.count)",
                                label: "Approved", color: Brand.success,
                                isSelected: filterStatus == .approved
                            ) { filterStatus = filterStatus == .approved ? nil : .approved }
                            ScheduleSummaryPill(
                                value: "\(rows.filter { $0.status == .denied }.count)",
                                label: "Denied", color: Brand.danger,
                                isSelected: filterStatus == .denied
                            ) { filterStatus = filterStatus == .denied ? nil : .denied }
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Brand.textTertiary)
                            TextField("Search doctor or specialty…", text: $searchText)
                                .font(.system(size: 14))
                                .foregroundStyle(Brand.textPrimary)
                                .tint(Brand.accent)
                            if !searchText.isEmpty {
                                Button { searchText = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Brand.textTertiary)
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 10))

                        if filtered.isEmpty {
                            Text(rows.isEmpty ? "No token requests yet." : "No requests match your filters.")
                                .font(.subheadline)
                                .foregroundStyle(Brand.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 32)
                        } else {
                            ForEach(filtered) { row in
                                ScheduleCardRow(
                                    row: row,
                                    onApprove: {
                                        tokens.approve(id: row.id)
                                        NotificationService.shared.notifyTokenDecision(approved: true, date: row.date)
                                    },
                                    onDeny: {
                                        tokens.deny(id: row.id)
                                        NotificationService.shared.notifyTokenDecision(approved: false, date: row.date)
                                    }
                                )
                                .cardStyle()
                            }
                        }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Compact Schedule Row (no scroll, fits screen)

private struct CompactScheduleRow: View {
    let row: AdminRow
    let height: CGFloat
    let onApprove: () -> Void
    let onDeny: () -> Void

    private var daysOut: Double { row.date.timeIntervalSinceNow / 86400 }
    private var urgencyColor: Color {
        daysOut < 1 ? Brand.danger : daysOut < 4 ? Brand.warning : Brand.success
    }

    var body: some View {
        HStack(spacing: 0) {
            // Date
            VStack(spacing: 0) {
                Text(row.date.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(urgencyColor).textCase(.uppercase)
                Text(row.date.formatted(.dateTime.day()))
                    .font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(urgencyColor)
            }
            .frame(width: 58)

            // Doctor
            VStack(alignment: .leading, spacing: 2) {
                Text("\(row.doctorName), \(row.credential)")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                Text(row.requestedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10)).foregroundStyle(Brand.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)

            // Specialty
            Text(row.specialty)
                .font(.system(size: 12)).foregroundStyle(Brand.textSecondary).lineLimit(1)
                .frame(width: 120, alignment: .leading)

            // Rate
            Text("$\(row.rate)/d")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.accent)
                .frame(width: 80, alignment: .center)

            // Status badge
            statusBadge
                .frame(width: 80, alignment: .center)

            // Actions
            HStack(spacing: 6) {
                if row.status == .pending {
                    Button(action: onApprove) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20)).foregroundStyle(Brand.success)
                    }.buttonStyle(.plain)
                    Button(action: onDeny) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20)).foregroundStyle(Brand.danger)
                    }.buttonStyle(.plain)
                }
            }
            .frame(width: 70, alignment: .center)
        }
        .frame(height: height)
        .background(daysOut < 1 ? Brand.danger.opacity(0.04) : Color.clear)
    }

    @ViewBuilder private var statusBadge: some View {
        let (label, color): (String, Color) = {
            switch row.status {
            case .pending:      return ("Pending", Brand.warning)
            case .approved:     return ("✓ Approved", Brand.success)
            case .autoApproved: return ("Auto", Brand.accent)
            case .denied:       return ("Denied", Brand.danger)
            }
        }()
        Text(label)
            .font(.system(size: 9, weight: .bold)).foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}

private extension Text {
    func scheduleHeader(width: CGFloat?) -> some View {
        self
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Brand.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
            .frame(width: width, alignment: width == nil ? .leading : .center)
            .padding(.horizontal, width == nil ? 4 : 0)
            .padding(.vertical, 8)
    }
}

// MARK: - Schedule Card Row

struct ScheduleCardRow: View {
    let row: AdminRow
    let onApprove: () -> Void
    let onDeny: () -> Void

    private var daysOut: Double { row.date.timeIntervalSinceNow / 86400 }
    private var urgencyColor: Color {
        if daysOut < 1 { return Brand.danger }
        if daysOut < 4 { return Brand.warning }
        return Brand.success
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Date badge
                VStack(spacing: 1) {
                    Text(row.date.formatted(.dateTime.month(.abbreviated)))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(urgencyColor)
                        .textCase(.uppercase)
                    Text(row.date.formatted(.dateTime.day()))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(urgencyColor)
                    Text(row.date.formatted(.dateTime.weekday(.short)))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(urgencyColor.opacity(0.7))
                }
                .frame(width: 42)
                .padding(.vertical, 8)
                .background(urgencyColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                // Doctor info
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(row.doctorName), \(row.credential)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Brand.textPrimary)
                    Text(row.specialty)
                        .font(.system(size: 13))
                        .foregroundStyle(Brand.textSecondary)
                    Text("Requested \(row.requestedAt.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.textTertiary)
                }

                Spacer(minLength: 0)

                // Right side
                VStack(alignment: .trailing, spacing: 6) {
                    Text("$\(row.rate)/day")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Brand.accent)
                    statusBadge(row.status)
                }
            }
            .padding(14)

            // Action buttons — only for pending
            if row.status == .pending {
                Divider()
                    .background(Brand.border)
                HStack(spacing: 10) {
                    Button(action: onDeny) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                            Text("Deny")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Brand.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Brand.danger)
                    }
                    .buttonStyle(.plain)

                    Button(action: onApprove) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                            Text("Approve")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Brand.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(Brand.success)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    row.status == .pending ? urgencyColor.opacity(0.3) : Brand.border,
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private func statusBadge(_ status: AdminRow.RowStatus) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case .pending:      return ("Pending", Brand.warning)
            case .approved:     return ("Approved", Brand.success)
            case .autoApproved: return ("Auto-Approved", Brand.accent)
            case .denied:       return ("Denied", Brand.danger)
            }
        }()
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}

// MARK: - Schedule Summary Pill

struct ScheduleSummaryPill: View {
    let value: String
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .white : color)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? .white.opacity(0.75) : Brand.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isSelected ? color : color.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : color.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

struct AdminRow: Identifiable {
    let id: UUID
    let doctorName: String
    let credential: String
    let specialty: String
    let date: Date
    let requestedAt: Date
    let rate: Int
    var status: RowStatus

    enum RowStatus { case pending, approved, autoApproved, denied }

    init(request: TokenStore.TokenRequest) {
        id = request.id
        doctorName = request.doctorName
        credential = request.credential
        specialty = request.specialty
        date = request.date
        requestedAt = request.requestedAt
        rate = Int(request.shiftRate ?? 0)
        switch request.status {
        case .pending: status = .pending
        case .approved: status = .approved
        case .autoApproved: status = .autoApproved
        case .denied: status = .denied
        }
    }
}

// MARK: - Alter Shifts (per-day shift editing)

struct AlterShiftsView: View {
    let profile: HospitalProfile?
    @ObservedObject private var hospitalService = Services.hospital
    @StateObject private var policyStore = SchedulingPolicyStore.shared
    @State private var calendarMonth = Date()
    @State private var selectedDate = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400))
    @State private var specialty = "Internal Medicine"
    @State private var rateFloor: Double = 1200
    @State private var useCustomRate = false
    @State private var flatRate: Double = 2000
    @State private var useAlgorithm = true
    @State private var suggestedRate: SuggestedRate? = nil
    @State private var didSave = false
    @State private var editingShiftID: UUID?

    private var hospitalID: UUID? { profile?.id }
    private var hospitalName: String { profile?.name ?? "" }
    private var isHourly: Bool { policyStore.policy.granularity == .hour }
    private var rateUnitLabel: String { isHourly ? "/hr" : "/day" }

    private var dayData: [CalendarHeatmap.DayData] {
        guard let hospitalID else { return [] }
        return HospitalDayInsights.calendarDayData(for: calendarMonth, hospitalID: hospitalID)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundGradient()
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Pick a Day", systemImage: "calendar")
                            Text("Each day has an on-call shift. Select a day below to view or customize it.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button { calendarMonth = Calendar.current.date(byAdding: .month, value: -1, to: calendarMonth) ?? calendarMonth } label: {
                                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.white.opacity(0.5))
                                }.buttonStyle(.plain)
                                Spacer()
                                Button { calendarMonth = Calendar.current.date(byAdding: .month, value: 1, to: calendarMonth) ?? calendarMonth } label: {
                                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.white.opacity(0.5))
                                }.buttonStyle(.plain)
                            }
                            CalendarHeatmap(month: calendarMonth, dayData: dayData, mode: .hospital, embedded: true) { date in
                                selectedDate = date.onlyDate()
                                loadShift(for: date.onlyDate())
                            }
                            .onChange(of: calendarMonth) { _, month in
                                guard let hospitalID else { return }
                                hospitalService.ensureMonthShifts(
                                    for: month,
                                    hospitalID: hospitalID,
                                    hospitalName: hospitalName,
                                    policy: policyStore.policy
                                )
                            }
                        }
                        .cardStyle()

                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(title: selectedDate.formatted(.dateTime.weekday(.wide).month().day()), systemImage: "slider.horizontal.3")
                            SpecialtyPicker(selection: $specialty)
                                .onChange(of: specialty) { _, _ in loadShift(for: selectedDate) }

                            Toggle(isOn: $useAlgorithm.animation()) {
                                Label("Use On Call pricing algorithm", systemImage: "sparkles")
                                    .font(.subheadline.weight(.medium))
                            }
                            .tint(Brand.accent)
                            .onChange(of: useAlgorithm) { _, _ in refreshRate() }

                            Divider()

                            HStack {
                                Text(useAlgorithm ? "Algorithm rate floor" : "Manual rate floor")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("$\(Int(rateFloor))\(rateUnitLabel)")
                                    .font(.headline)
                                    .foregroundStyle(Color.accentColor)
                            }

                            if useAlgorithm {
                                if let sr = suggestedRate {
                                    Text("\(sr.breakdown.variableCount) pricing variables · \(Int(sr.breakdown.confidence * 100))% confidence")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                let baseRate = policyStore.policy.specialtyBaseRates[specialty] ?? 0
                                if baseRate > 0 {
                                    Text("Floor capped at base rate: $\(Int(baseRate))\(rateUnitLabel)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Button { computeRate() } label: {
                                    Label("Recalculate", systemImage: "arrow.clockwise")
                                        .font(.caption.weight(.semibold))
                                }
                            } else {
                                let baseRate = policyStore.policy.specialtyBaseRates[specialty] ?? 0
                                let minRate = max(isHourly ? 80.0 : 800.0, baseRate)
                                Stepper("", value: $rateFloor, in: minRate...(isHourly ? 400 : 5000), step: isHourly ? 5 : 50)
                                    .labelsHidden()
                                if baseRate > 0 {
                                    Text("Minimum: $\(Int(minRate))\(rateUnitLabel) (specialty base rate)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }

                            if useAlgorithm, let sr = suggestedRate, !sr.breakdown.allComponents.isEmpty {
                                PricingFactorBreakdownView(components: sr.breakdown.allComponents)
                            }

                            Divider()
                            Toggle("Override with flat rate", isOn: $useCustomRate.animation())
                            if useCustomRate {
                                HStack {
                                    Text("Flat rate").foregroundStyle(.secondary)
                                    Spacer()
                                    Text("$\(Int(flatRate))\(rateUnitLabel)").font(.headline).foregroundStyle(Color.accentColor)
                                }
                                Stepper("", value: $flatRate, in: rateFloor...(isHourly ? 600 : 8000), step: isHourly ? 5 : 50).labelsHidden()
                            }
                        }
                        .cardStyle()

                        Button { saveShift() } label: {
                            Group {
                                if didSave {
                                    Label("Saved!", systemImage: "checkmark.circle.fill")
                                } else {
                                    Text("Save Shift for This Day")
                                }
                            }
                            .font(.headline).frame(maxWidth: .infinity).padding()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding()
                }
            }
            .navigationTitle("Alter Shifts")
            .onAppear {
                if let hospitalID {
                    hospitalService.ensureDailyShifts(
                        from: Date(),
                        days: 120,
                        hospitalID: hospitalID,
                        hospitalName: hospitalName,
                        policy: policyStore.policy
                    )
                    hospitalService.ensureMonthShifts(
                        for: calendarMonth,
                        hospitalID: hospitalID,
                        hospitalName: hospitalName,
                        policy: policyStore.policy
                    )
                    loadShift(for: selectedDate)
                }
            }
        }
    }

    private func loadShift(for date: Date) {
        guard let hospitalID else { return }
        hospitalService.ensureMonthShifts(
            for: date,
            hospitalID: hospitalID,
            hospitalName: hospitalName,
            policy: policyStore.policy
        )
        let shift = hospitalService.shift(
            on: date,
            specialty: specialty,
            hospitalID: hospitalID,
            hospitalName: hospitalName,
            policy: policyStore.policy
        )
        editingShiftID = shift.id
        useAlgorithm = shift.usesAlgorithmPricing
        if case .flat(let r) = shift.escalationMode {
            useCustomRate = true
            flatRate = r
        } else {
            useCustomRate = false
        }
        refreshRate(fallback: shift.rateFloor)
    }

    private func refreshRate(fallback: Double? = nil) {
        if useAlgorithm {
            computeRate()
        } else if let fallback {
            rateFloor = fallback
        }
    }

    private func computeRate() {
        guard let hospitalID else {
            suggestedRate = OnCallPricingEngine.compute(
                specialty: specialty,
                date: selectedDate,
                granularity: policyStore.policy.granularity
            ).toSuggestedRate()
            rateFloor = max(suggestedRate?.floor ?? rateFloor,
                            policyStore.policy.specialtyBaseRates[specialty] ?? 0)
            return
        }
        suggestedRate = ProposedRateStore.shared.suggestedRate(
            specialty: specialty,
            date: selectedDate,
            hospitalID: hospitalID
        )
        rateFloor = max(suggestedRate?.floor ?? rateFloor,
                        policyStore.policy.specialtyBaseRates[specialty] ?? 0)
    }

    private func saveShift() {
        guard let hospitalID else { return }
        if useAlgorithm { computeRate() }
        let mode: EscalationMode = useCustomRate ? .flat(flatRate) : .automatic
        let shift = Shift(
            id: editingShiftID ?? UUID(),
            hospitalID: hospitalID,
            hospital: hospitalName.isEmpty ? "Hospital" : hospitalName,
            specialty: specialty,
            start: selectedDate,
            durationHours: isHourly ? 12 : 24,
            rateFloor: rateFloor,
            rateUnit: isHourly ? .perHour : .perDay,
            escalationMode: mode,
            usesAlgorithmPricing: useAlgorithm
        )
        hospitalService.upsertShift(shift)
        editingShiftID = shift.id
        didSave = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didSave = false }
    }
}

// MARK: - Pricing factor breakdown (Alter Shifts)

private struct PricingFactorBreakdownView: View {
    let components: [PricingFactorComponent]

    private var grouped: [(String, [PricingFactorComponent])] {
        Dictionary(grouping: components.filter { $0.weight > 0 || $0.id == "base" }, by: \.category)
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Algorithm breakdown")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            ForEach(grouped, id: \.0) { category, items in
                Text(category.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Brand.textTertiary)
                ForEach(items) { item in
                    HStack {
                        Text(item.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(item.displayValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.multiplier >= 1.0 ? Brand.accent : Brand.textSecondary)
                    }
                }
            }
        }
        .padding(10)
        .background(Brand.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Hospital management screens

struct HospitalOpenShiftsView: View {
    let profile: HospitalProfile?
    @ObservedObject private var hospitalService = Services.hospital
    @ObservedObject private var assignments = AssignedShiftsStore.shared

    private var openShifts: [Shift] {
        hospitalService.shifts
            .filter { !$0.isPast && !assignments.isShiftFilled($0.id) }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        ZStack {
            BackgroundGradient()
            ScrollView {
                VStack(spacing: 10) {
                    if openShifts.isEmpty {
                        Text("All shifts are filled.").foregroundStyle(.secondary).padding(40)
                    } else {
                        ForEach(openShifts) { shift in
                            ShiftRow(shift: shift).cardStyle()
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Open Shifts")
    }
}

// MARK: - Hospital Analytics

struct HospitalAnalyticsView: View {
    let profile: HospitalProfile?
    @ObservedObject private var store = AssignedShiftsStore.shared
    @ObservedObject private var ledger = PenaltyLedgerStore.shared
    @ObservedObject private var hospitalService = Services.hospital

    var body: some View {
        ZStack {
            BackgroundGradient()
            ScrollView {
                VStack(spacing: 14) {
                    topStatsCard
                    timeBucketsRow
                    savingsSummaryCard
                    specialtyListCard
                }
                .padding(18)
            }
        }
        .navigationTitle("Analytics")
    }

    // MARK: Data

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var yr: String { "'\(currentYear % 100)" }  // e.g. "'26"

    private var hospitalShifts: [AssignedShiftsStore.AssignedShift] {
        guard let hid = profile?.id else { return store.assignedShifts }
        return store.assignedShifts.filter { $0.shift.hospitalID == hid }
    }
    /// Shifts whose shift date falls in the current calendar year.
    private var yearShifts: [AssignedShiftsStore.AssignedShift] {
        hospitalShifts.filter { Calendar.current.component(.year, from: $0.shift.date) == currentYear }
    }
    private var canceledShifts: [AssignedShiftsStore.AssignedShift] {
        yearShifts.filter { $0.status == .canceled }
    }
    private var tradedShifts: [AssignedShiftsStore.AssignedShift] {
        yearShifts.filter { $0.status == .tradedPending || $0.status == .tradedComplete }
    }
    private var hospitalLedger: [PenaltyLedgerStore.Entry] {
        guard let hid = profile?.id else { return ledger.entries }
        return ledger.entries.filter { $0.hospitalID == hid }
    }
    /// Ledger entries logged in the current calendar year.
    private var yearLedger: [PenaltyLedgerStore.Entry] {
        hospitalLedger.filter { Calendar.current.component(.year, from: $0.createdAt) == currentYear }
    }

    /// True when no real data exists yet — drives demo/placeholder values.
    private var noRealData: Bool { hospitalShifts.isEmpty && hospitalLedger.isEmpty }

    private var tradedCount:   Int { noRealData ? 34  : tradedShifts.count }
    private var canceledCount: Int { noRealData ? 23  : canceledShifts.count }
    private var tradePercent:  Double { noRealData ? 18.4 : Double(tradedShifts.count)   / Double(max(1, yearShifts.count)) * 100 }
    private var cancelPercent: Double { noRealData ? 11.8 : Double(canceledShifts.count) / Double(max(1, yearShifts.count)) * 100 }

    private struct MockBuckets {
        static let tradeLt1mo = 12; static let tradeOne2Three = 16; static let tradeGt3mo = 6
        static let cancelLt1mo = 9; static let cancelOne2Three = 10; static let cancelGt3mo = 4
    }

    /// Count ledger actions whose lead time (shift date − action date) is in [minDays, maxDays).
    private func timeBucket(type: PenaltyLedgerStore.EntryType, minDays: Int, maxDays: Int?) -> Int {
        if noRealData {
            switch (type, minDays) {
            case (.trade, 0):   return MockBuckets.tradeLt1mo
            case (.trade, 30):  return MockBuckets.tradeOne2Three
            case (.trade, 90):  return MockBuckets.tradeGt3mo
            case (.cancel, 0):  return MockBuckets.cancelLt1mo
            case (.cancel, 30): return MockBuckets.cancelOne2Three
            case (.cancel, 90): return MockBuckets.cancelGt3mo
            default: return 0
            }
        }
        return yearLedger.filter { entry in
            guard entry.type == type,
                  let a = hospitalShifts.first(where: { $0.shift.id == entry.shiftID }) else { return false }
            let d = a.shift.date.timeIntervalSince(entry.createdAt) / 86400
            guard d >= 0 else { return false }
            return d >= Double(minDays) && (maxDays.map { d < Double($0) } ?? true)
        }.count
    }

    private var daysElapsedThisYear: Double {
        let cal = Calendar.current
        guard let yearStart = cal.date(from: DateComponents(year: currentYear, month: 1, day: 1)) else { return 1 }
        return max(1, Date().timeIntervalSince(yearStart) / 86400)
    }
    private var yearPenaltyRevenue: Double {
        yearLedger.map { NSDecimalNumber(decimal: $0.amount).doubleValue }.reduce(0, +)
    }
    private var savingsPerDay: Double { noRealData ? 147.0 : yearPenaltyRevenue / daysElapsedThisYear }

    // MARK: Views

    private var topStatsCard: some View {
        VStack(spacing: 0) {
            // Row 1 — avg percentages (top-left: trade, top-right: cancel)
            HStack(spacing: 0) {
                AnalyticsCornerStat(label: "Avg Traded \(yr)",   value: String(format: "%.1f%%", tradePercent),  color: Brand.accent)
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                AnalyticsCornerStat(label: "Avg Canceled \(yr)", value: String(format: "%.1f%%", cancelPercent), color: Brand.danger)
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            // Row 2 — totals (bottom-left: total traded, bottom-right: total canceled)
            HStack(spacing: 0) {
                AnalyticsCornerStat(label: "Total Traded \(yr)",   value: "\(tradedCount)",   color: Brand.accent, large: true)
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                AnalyticsCornerStat(label: "Total Canceled \(yr)", value: "\(canceledCount)", color: Brand.danger, large: true)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.075), Color.white.opacity(0.03)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.04)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
    }

    private var timeBucketsRow: some View {
        HStack(spacing: 12) {
            AnalyticsTimeBucketPanel(
                title: "Traded",  color: Brand.accent,
                lt1mo:    timeBucket(type: .trade, minDays: 0,  maxDays: 30),
                one2three: timeBucket(type: .trade, minDays: 30, maxDays: 90),
                gt3mo:    timeBucket(type: .trade, minDays: 90, maxDays: nil)
            )
            AnalyticsTimeBucketPanel(
                title: "Canceled", color: Brand.danger,
                lt1mo:    timeBucket(type: .cancel, minDays: 0,  maxDays: 30),
                one2three: timeBucket(type: .cancel, minDays: 30, maxDays: 90),
                gt3mo:    timeBucket(type: .cancel, minDays: 90, maxDays: nil)
            )
        }
    }

    // Non-tappable overall savings header
    private var savingsSummaryCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "banknote.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.success)
                .frame(width: 36, height: 36)
                .background(Brand.success.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Amount Saved per Day")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary)
                Text("Penalty revenue recovered overall")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.textSecondary)
            }
            Spacer()
            Text(String(format: "$%.0f", savingsPerDay))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.success)
        }
        .cardStyle()
    }

    // Inline specialty list — each row navigates to the chart
    private var specialtyListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "By Specialty", systemImage: "stethoscope")
                .padding(.bottom, 12)

            let revenues = specialtyRevenues
            if revenues.isEmpty {
                Text("No penalty revenue recorded yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.textSecondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(revenues.enumerated()), id: \.offset) { i, item in
                    VStack(spacing: 0) {
                        if i > 0 { SubtleDivider().padding(.vertical, 10) }
                        NavigationLink(destination: SpecialtySavingsChart(specialty: item.0, profile: profile)) {
                            HStack(spacing: 12) {
                                Image(systemName: "stethoscope")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Brand.success)
                                    .frame(width: 30, height: 30)
                                    .background(Brand.success.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.0)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Brand.textPrimary)
                                    Text("per day")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Brand.textTertiary)
                                }
                                Spacer()
                                Text(String(format: "$%.0f", item.1))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundStyle(Brand.success)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Brand.textTertiary)
                                    .padding(.leading, 2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .cardStyle()
    }

    private var specialtyRevenues: [(String, Double)] {
        if noRealData {
            return [
                ("Cardiology",         58.0),
                ("Emergency Medicine", 42.0),
                ("Orthopedics",        27.0),
                ("General Surgery",    15.0),
                ("Internal Medicine",   5.0)
            ]
        }
        // Year-scoped: only entries logged in the current calendar year
        let bySpecialty = Dictionary(grouping: yearLedger) { entry -> String in
            hospitalShifts.first(where: { $0.shift.id == entry.shiftID })?.shift.specialty ?? ""
        }
        return bySpecialty
            .compactMap { specialty, entries -> (String, Double)? in
                guard !specialty.isEmpty else { return nil }
                let total = entries.map { NSDecimalNumber(decimal: $0.amount).doubleValue }.reduce(0, +)
                return (specialty, total / daysElapsedThisYear)
            }
            .sorted { $0.1 > $1.1 }
    }
}

// MARK: - Analytics corner stat (4-quadrant cell)

private struct AnalyticsCornerStat: View {
    let label: String
    let value: String
    let color: Color
    var large: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Brand.textTertiary)
            Text(value)
                .font(.system(size: large ? 34 : 26, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }
}

// MARK: - Time bucket panel

private struct AnalyticsTimeBucketPanel: View {
    let title: String
    let color: Color
    let lt1mo: Int
    let one2three: Int
    let gt3mo: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary)
            }
            SubtleDivider()
            HStack(spacing: 0) {
                AnalyticsMiniStat(label: "<1 mo",  count: lt1mo,    color: color)
                Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1, height: 40)
                AnalyticsMiniStat(label: "1–3 mo", count: one2three, color: color)
                Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1, height: 40)
                AnalyticsMiniStat(label: ">3 mo",  count: gt3mo,    color: color)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct AnalyticsMiniStat: View {
    let label: String
    let count: Int
    let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Brand.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Savings detail (specialty list)

// MARK: - Specialty savings chart

struct SpecialtySavingsChart: View {
    let specialty: String
    let profile: HospitalProfile?
    @ObservedObject private var ledger = PenaltyLedgerStore.shared
    @ObservedObject private var store = AssignedShiftsStore.shared
    @State private var mode: ChartMode = .month

    enum ChartMode: String, CaseIterable { case month = "Per Month"; case year = "Per Year" }

    struct DataPoint: Identifiable {
        let id = UUID()
        let label: String
        let amount: Double
        let sortKey: Date
    }

    var body: some View {
        ZStack {
            BackgroundGradient()
            ScrollView {
                VStack(spacing: 14) {
                    topCard
                    bucketsRow
                    savingsSummaryCard
                    modeToggle
                    chartCard
                }
                .padding(18)
            }
        }
        .navigationTitle(specialty)
    }

    // MARK: Sub-views

    private var topCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                AnalyticsCornerStat(label: "Avg Traded \(yr)",   value: String(format: "%.1f%%", tradePercent),  color: Brand.accent)
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                AnalyticsCornerStat(label: "Avg Canceled \(yr)", value: String(format: "%.1f%%", cancelPercent), color: Brand.danger)
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            HStack(spacing: 0) {
                AnalyticsCornerStat(label: "Total Traded \(yr)",   value: "\(tradedCount)",   color: Brand.accent, large: true)
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                AnalyticsCornerStat(label: "Total Canceled \(yr)", value: "\(canceledCount)", color: Brand.danger, large: true)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.075), Color.white.opacity(0.03)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Brand.cardRadius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.04)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
    }

    private var bucketsRow: some View {
        HStack(spacing: 12) {
            AnalyticsTimeBucketPanel(
                title: "Traded",  color: Brand.accent,
                lt1mo:     specBucket(.trade, 0,  30),
                one2three: specBucket(.trade, 30, 90),
                gt3mo:     specBucket(.trade, 90, nil)
            )
            AnalyticsTimeBucketPanel(
                title: "Canceled", color: Brand.danger,
                lt1mo:     specBucket(.cancel, 0,  30),
                one2three: specBucket(.cancel, 30, 90),
                gt3mo:     specBucket(.cancel, 90, nil)
            )
        }
    }

    private var savingsSummaryCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "banknote.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Brand.success)
                .frame(width: 36, height: 36)
                .background(Brand.success.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Amount Saved per Day")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.textPrimary)
                Text("Total recovered: \(String(format: "$%.0f", totalRevenue))")
                    .font(.system(size: 12))
                    .foregroundStyle(Brand.textSecondary)
            }
            Spacer()
            Text(String(format: "$%.0f", savingsPerDay))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Brand.success)
        }
        .cardStyle()
    }

    private var modeToggle: some View {
        HStack(spacing: 4) {
            ForEach(ChartMode.allCases, id: \.self) { m in
                Button { withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) { mode = m } } label: {
                    Text(m.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(mode == m ? .white : Brand.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if mode == m {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.accentGradient)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: mode == .month ? "Last 12 Months" : "2026 – 2028",
                          systemImage: "chart.bar.fill")
            let data = chartData
            if data.allSatisfy({ $0.amount == 0 }) {
                Text("No data for this period.")
                    .font(.system(size: 13))
                    .foregroundStyle(Brand.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                Chart(data) { point in
                    BarMark(
                        x: .value("Period", point.label),
                        y: .value("Amount", point.amount)
                    )
                    .foregroundStyle(Brand.accentGradient)
                    .cornerRadius(5)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        if let d = v.as(Double.self) {
                            AxisValueLabel {
                                Text("$\(Int(d))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Brand.textTertiary)
                            }
                        }
                        AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                    }
                }
                .chartXAxis {
                    AxisMarks { v in
                        AxisValueLabel {
                            if let s = v.as(String.self) {
                                Text(s).font(.system(size: 10)).foregroundStyle(Brand.textTertiary)
                            }
                        }
                    }
                }
                .frame(height: 220)
            }
        }
        .cardStyle()
    }

    // MARK: Data

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }
    private var yr: String { "'\(currentYear % 100)" }

    /// Scale factor 0.35–1.0 unique per specialty name for demo variety.
    private var mockScale: Double {
        let sum = specialty.unicodeScalars.reduce(0) { $0 + $1.value }
        return 0.35 + Double(sum % 65) / 100.0
    }

    private var allSpecialtyShifts: [AssignedShiftsStore.AssignedShift] {
        let hid = profile?.id
        return store.assignedShifts.filter { a in
            a.shift.specialty == specialty && (hid == nil || a.shift.hospitalID == hid)
        }
    }
    /// Shifts in the current calendar year.
    private var specialtyShifts: [AssignedShiftsStore.AssignedShift] {
        allSpecialtyShifts.filter { Calendar.current.component(.year, from: $0.shift.date) == currentYear }
    }
    private var specialtyTradedShifts: [AssignedShiftsStore.AssignedShift] {
        specialtyShifts.filter { $0.status == .tradedPending || $0.status == .tradedComplete }
    }
    private var specialtyCanceledShifts: [AssignedShiftsStore.AssignedShift] {
        specialtyShifts.filter { $0.status == .canceled }
    }
    private var allSpecialtyLedger: [PenaltyLedgerStore.Entry] {
        let hid = profile?.id
        return ledger.entries.filter { entry in
            (hid == nil || entry.hospitalID == hid) &&
            allSpecialtyShifts.first(where: { $0.shift.id == entry.shiftID }) != nil
        }
    }
    /// Ledger entries for this specialty in the current calendar year.
    private var specialtyLedger: [PenaltyLedgerStore.Entry] {
        allSpecialtyLedger.filter { Calendar.current.component(.year, from: $0.createdAt) == currentYear }
    }
    private var noRealData: Bool { specialtyLedger.isEmpty && specialtyShifts.isEmpty }

    private var tradedCount:   Int    { noRealData ? Int((34.0 * (0.4 + mockScale * 0.6)).rounded()) : specialtyTradedShifts.count }
    private var canceledCount: Int    { noRealData ? Int((23.0 * (0.3 + mockScale * 0.7)).rounded()) : specialtyCanceledShifts.count }
    private var tradePercent:  Double { noRealData ? ((18.4 * (0.5 + mockScale * 0.8)) * 10).rounded() / 10 : Double(specialtyTradedShifts.count)   / Double(max(1, specialtyShifts.count)) * 100 }
    private var cancelPercent: Double { noRealData ? ((11.8 * (0.4 + mockScale * 0.9)) * 10).rounded() / 10 : Double(specialtyCanceledShifts.count) / Double(max(1, specialtyShifts.count)) * 100 }

    private func specBucket(_ type: PenaltyLedgerStore.EntryType, _ minDays: Int, _ maxDays: Int?) -> Int {
        if noRealData {
            let bases: [PenaltyLedgerStore.EntryType: [Int]] = [.trade: [12, 16, 6], .cancel: [9, 10, 4]]
            let idx = minDays == 0 ? 0 : minDays == 30 ? 1 : 2
            let base = Double(bases[type]?[idx] ?? 0)
            return Int((base * (0.4 + mockScale * 0.6)).rounded())
        }
        return specialtyLedger.filter { entry in
            guard entry.type == type,
                  let a = allSpecialtyShifts.first(where: { $0.shift.id == entry.shiftID }) else { return false }
            let d = a.shift.date.timeIntervalSince(entry.createdAt) / 86400
            guard d >= 0 else { return false }
            return d >= Double(minDays) && (maxDays.map { d < Double($0) } ?? true)
        }.count
    }

    private var daysElapsedThisYear: Double {
        let cal = Calendar.current
        guard let yearStart = cal.date(from: DateComponents(year: currentYear, month: 1, day: 1)) else { return 1 }
        return max(1, Date().timeIntervalSince(yearStart) / 86400)
    }

    /// Plausible monthly amounts, scaled per specialty (12 months oldest → newest).
    private var mockMonthlyAmounts: [Double] {
        let base = 500.0 + mockScale * 600
        return [0.72, 0.58, 0.91, 0.83, 1.05, 0.94, 1.18, 1.02, 1.31, 1.14, 1.42, 1.27].map { $0 * base }
    }

    private var savingsPerDay: Double {
        if noRealData { return (mockMonthlyAmounts.reduce(0, +) / Double(mockMonthlyAmounts.count) / 30.44).rounded() }
        return specialtyLedger.map { NSDecimalNumber(decimal: $0.amount).doubleValue }.reduce(0, +) / daysElapsedThisYear
    }

    private var totalRevenue: Double {
        if noRealData { return (mockMonthlyAmounts.reduce(0, +) * 3).rounded() }
        return allSpecialtyLedger.map { NSDecimalNumber(decimal: $0.amount).doubleValue }.reduce(0, +)
    }

    private var chartData: [DataPoint] {
        let cal = Calendar.current
        let thisYear = cal.component(.year, from: Date())

        if noRealData {
            switch mode {
            case .month:
                let now = Date()
                let fmt = DateFormatter(); fmt.dateFormat = "MMM yyyy"
                let amounts = mockMonthlyAmounts
                return (0..<12).reversed().enumerated().compactMap { idx, offset -> DataPoint? in
                    guard let base = cal.date(byAdding: .month, value: -offset, to: now),
                          let start = cal.date(from: cal.dateComponents([.year, .month], from: base)) else { return nil }
                    return DataPoint(label: fmt.string(from: start), amount: amounts[idx], sortKey: start)
                }
            case .year:
                // Show current year + 2 projected future years
                let monthlyTotal = mockMonthlyAmounts.reduce(0, +)
                let yearAmounts: [Double] = [
                    (monthlyTotal * 0.58).rounded(),   // current year YTD (~7 months in)
                    (monthlyTotal * 1.22).rounded(),   // next year projected
                    (monthlyTotal * 1.51).rounded()    // year after projected
                ]
                return zip([thisYear, thisYear + 1, thisYear + 2], yearAmounts).map { year, amt in
                    DataPoint(label: "\(year)", amount: amt,
                              sortKey: cal.date(from: DateComponents(year: year)) ?? Date())
                }
            }
        }

        let sorted = specialtyLedger.sorted { $0.createdAt < $1.createdAt }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM ''yy"
        switch mode {
        case .month:
            let now = Date()
            return (0..<12).reversed().compactMap { offset -> DataPoint? in
                guard let base = cal.date(byAdding: .month, value: -offset, to: now) else { return nil }
                let comps = cal.dateComponents([.year, .month], from: base)
                guard let start = cal.date(from: comps),
                      let end   = cal.date(byAdding: .month, value: 1, to: start) else { return nil }
                let total = sorted.filter { $0.createdAt >= start && $0.createdAt < end }
                    .map { NSDecimalNumber(decimal: $0.amount).doubleValue }.reduce(0, +)
                return DataPoint(label: fmt.string(from: start), amount: total, sortKey: start)
            }
        case .year:
            let years = Set(sorted.map { cal.component(.year, from: $0.createdAt) }).sorted()
            guard !years.isEmpty else {
                return [DataPoint(label: "\(thisYear)", amount: 0, sortKey: Date())]
            }
            return years.map { year -> DataPoint in
                let total = sorted.filter { cal.component(.year, from: $0.createdAt) == year }
                    .map { NSDecimalNumber(decimal: $0.amount).doubleValue }.reduce(0, +)
                return DataPoint(label: "\(year)", amount: total,
                                 sortKey: cal.date(from: DateComponents(year: year)) ?? Date())
            }
        }
    }
}

struct HospitalBillingView: View {
    let profile: HospitalProfile?
    @ObservedObject private var hospitalService = Services.hospital
    @ObservedObject private var assignments = AssignedShiftsStore.shared

    private var committedTotal: Int {
        hospitalService.shifts
            .filter { assignments.isShiftFilled($0.id) }
            .reduce(0) { $0 + Int($1.totalEarnings) }
    }

    var body: some View {
        ZStack {
            BackgroundGradient()
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "This Month")
                        HStack {
                            Text("Committed payouts").foregroundStyle(.secondary)
                            Spacer()
                            Text("$\(committedTotal)").font(.title2.bold()).foregroundStyle(Color.accentColor)
                        }
                        Text("Based on filled shifts at current rates.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Recent Filled Shifts")
                        ForEach(Array(filledShifts.prefix(8))) { shift in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(shift.displayDateLabel).font(.subheadline.weight(.semibold))
                                    Text(shift.specialty).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("$\(Int(shift.totalEarnings))").font(.headline).foregroundStyle(Color.accentColor)
                            }
                            if shift.id != filledShifts.prefix(8).last?.id { Divider() }
                        }
                    }
                    .cardStyle()
                }
                .padding()
            }
        }
        .navigationTitle("Billing")
    }

    private var filledShifts: [Shift] {
        hospitalService.shifts.filter { assignments.isShiftFilled($0.id) }
    }
}

private struct PostField: View {
    let label: String; @Binding var text: String
    var body: some View {
        HStack { Text(label).foregroundStyle(.secondary).frame(minWidth: 80, alignment: .leading); TextField(label, text: $text).font(.body) }.font(Brand.brandFont)
    }
}

private struct SpecialtyPicker: View {
    @Binding var selection: String
    var body: some View { HStack { Text("Specialty").foregroundStyle(.secondary).font(Brand.brandFont); Spacer(); Picker("", selection: $selection) { ForEach(DemoData.specialties, id: \.self) { Text($0).tag($0) } } } }
}

// MARK: - Candidates

struct CandidatesView: View {
    @EnvironmentObject var store: DoctorRosterStore
    @State private var filterSpecialty = "All"; @State private var showAutoOnly = false

    private var filtered: [DoctorSummary] { store.doctors.filter { (filterSpecialty == "All" || $0.specialty == filterSpecialty) && (!showAutoOnly || $0.isAutoApproved) } }

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundGradient()
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Auto-approved only", isOn: $showAutoOnly.animation()).font(Brand.brandFont)
                            Divider()
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    FilterChip(label: "All", isSelected: filterSpecialty == "All") { filterSpecialty = "All" }
                                    ForEach(Array(Set(store.doctors.map { $0.specialty })).sorted(), id: \.self) { sp in FilterChip(label: sp, isSelected: filterSpecialty == sp) { filterSpecialty = sp } }
                                }
                            }
                        }
                        .cardStyle()
                        if filtered.isEmpty {
                            Text("No doctors match filters.").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity).cardStyle()
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(filtered) { doc in
                                    NavigationLink(destination: DoctorDetailView(doctor: doc, onToggleApprove: { store.toggleAutoApprove(id: doc.id) })) {
                                        DoctorRow(doctor: doc) { store.toggleAutoApprove(id: doc.id) }
                                    }
                                    .buttonStyle(.plain)
                                    if doc != filtered.last { Divider() }
                                }
                            }
                            .cardStyle()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Doctors")
        }
    }
}

// MARK: - Doctor Detail View

struct DoctorDetailView: View {
    let doctor: DoctorSummary
    let onToggleApprove: () -> Void
    @State private var calendarMonth = Date()
    @ObservedObject private var assignedStore = AssignedShiftsStore.shared
    @ObservedObject private var rosterStore = DoctorRosterStore.shared

    private var currentDoctor: DoctorSummary {
        rosterStore.doctors.first { $0.id == doctor.id } ?? doctor
    }

    private var scheduledDates: Set<Date> {
        Set(
            assignedStore.assignedShifts
                .filter { $0.doctorID == doctor.id && $0.status != .canceled }
                .map { Calendar.current.startOfDay(for: $0.shift.start) }
        )
    }

    private var scheduledCount: Int { scheduledDates.count }

    var body: some View {
        ZStack {
            BackgroundGradient()
            ScrollView {
                VStack(spacing: 16) {
                    // Profile card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Color.accentColor.opacity(0.15)).frame(width: 60, height: 60)
                                Text(String(doctor.name.prefix(1)))
                                    .font(.title2.bold()).foregroundStyle(Color.accentColor)
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(doctor.name), \(doctor.credential)")
                                    .font(.headline)
                                Text(doctor.specialty)
                                    .font(.subheadline).foregroundStyle(.secondary)
                                VerificationBadge(status: doctor.verificationStatus)
                            }
                            Spacer()
                            if currentDoctor.isAutoApproved {
                                Label("Auto", systemImage: "bolt.fill")
                                    .font(.caption2.weight(.bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Color.green, in: Capsule())
                            }
                        }
                        Divider().opacity(0.4)
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("NPI").font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(0.8)
                                Text(doctor.npi.isEmpty ? "—" : doctor.npi)
                                    .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                            }
                            Divider().frame(height: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("UPCOMING SHIFTS").font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(0.8)
                                Text("\(scheduledCount)").font(.subheadline.weight(.medium))
                            }
                        }
                        Divider().opacity(0.4)
                        Button {
                            withAnimation(.spring(response: 0.3)) { onToggleApprove() }
                        } label: {
                            HStack {
                                Image(systemName: currentDoctor.isAutoApproved ? "star.fill" : "star")
                                    .foregroundStyle(currentDoctor.isAutoApproved ? .yellow : .secondary)
                                Text(currentDoctor.isAutoApproved ? "Remove auto-approval" : "Grant auto-approval")
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .cardStyle()

                    // Schedule calendar
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Schedule", systemImage: "calendar")
                        HStack {
                            Button { calendarMonth = Calendar.current.date(byAdding: .month, value: -1, to: calendarMonth) ?? calendarMonth } label: {
                                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white.opacity(0.5))
                            }.buttonStyle(.plain)
                            Spacer()
                            Text(calendarMonth.formatted(.dateTime.month(.wide).year()))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Button { calendarMonth = Calendar.current.date(byAdding: .month, value: 1, to: calendarMonth) ?? calendarMonth } label: {
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white.opacity(0.5))
                            }.buttonStyle(.plain)
                        }

                        DoctorScheduleCalendar(month: calendarMonth, scheduledDates: scheduledDates)

                        HStack(spacing: 16) {
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 3).fill(Color.green.opacity(0.65)).frame(width: 12, height: 12)
                                Text("Scheduled").font(.caption2).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.1)).frame(width: 12, height: 12)
                                Text("Available").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .cardStyle()
                }
                .padding()
            }
        }
        .navigationTitle(doctor.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DoctorScheduleCalendar: View {
    let month: Date
    let scheduledDates: Set<Date>

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let dayLabels = ["S","M","T","W","T","F","S"]

    private var days: [Date?] {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let first = cal.date(from: comps) else { return [] }
        let offset = cal.component(.weekday, from: first) - 1
        var result: [Date?] = Array(repeating: nil, count: offset)
        for d in 1...range.count {
            result.append(cal.date(byAdding: .day, value: d - 1, to: first))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Array(dayLabels.enumerated()), id: \.offset) { _, d in
                    Text(d).font(.caption2.weight(.bold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let isScheduled = scheduledDates.contains(Calendar.current.startOfDay(for: date))
                        let isPast = date < Calendar.current.startOfDay(for: Date())
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isScheduled
                                      ? Color.green.opacity(isPast ? 0.22 : 0.55)
                                      : Color.white.opacity(isPast ? 0.03 : 0.08))
                            Text("\(Calendar.current.component(.day, from: date))")
                                .font(.caption.weight(isScheduled ? .semibold : .regular))
                                .foregroundStyle(isScheduled
                                                 ? Color.white.opacity(isPast ? 0.5 : 1.0)
                                                 : Color.white.opacity(isPast ? 0.25 : 0.45))
                        }
                        .frame(height: 34)
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }
        }
    }
}

// MARK: - Doctor Row

private struct DoctorRow: View {
    let doctor: DoctorSummary; let onToggleApprove: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            ZStack { Circle().fill(Color.accentColor.opacity(0.12)).frame(width: 42, height: 42); Text(String(doctor.name.prefix(1))).font(.headline).foregroundStyle(Color.accentColor) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(doctor.name), \(doctor.credential)").font(.headline)
                    if doctor.isAutoApproved { Label("Auto", systemImage: "bolt.fill").font(.caption2.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 2).background(Color.green, in: Capsule()) }
                }
                HStack(spacing: 6) { Text(doctor.specialty).font(.subheadline).foregroundStyle(.secondary); VerificationBadge(status: doctor.verificationStatus, compact: true) }
            }
            Spacer()
            Button { withAnimation(.spring(response: 0.3)) { onToggleApprove() } } label: {
                Image(systemName: doctor.isAutoApproved ? "star.fill" : "star").foregroundStyle(doctor.isAutoApproved ? Color.yellow : Color.secondary).font(.title3)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8).font(Brand.brandFont)
    }
}

private struct FilterChip: View {
    let label: String; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) { Text(label).font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 6).background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1), in: Capsule()).foregroundStyle(isSelected ? Color.white : Color.primary) }
            .buttonStyle(.plain).animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Preview

#Preview { ContentView() }
// 
