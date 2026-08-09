import SwiftUI

// MARK: - Auth Screen (Sign In / Sign Up)

struct AuthView: View {
    @ObservedObject var auth: AuthService
    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var selectedRole: UserRole = .doctor
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showDevRolePicker = false
    @Namespace private var ns

    enum AuthMode { case signIn, signUp }

    var body: some View {
        ZStack {
            // Background — deep navy with subtle grid
            Color(hex: "0A0F1E").ignoresSafeArea()
            MeshBackground()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Logo + wordmark
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(colors: [Color(hex: "4F8EF7"), Color(hex: "A78BFA")],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                            Text("On Call")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        Text("Smarter on-call scheduling")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .tracking(0.5)
                    }
                    .padding(.top, 64)
                    .padding(.bottom, 48)

                    // Card
                    VStack(spacing: 0) {
                        // Tab switcher
                        HStack(spacing: 0) {
                            TabPill(label: "Sign in", isActive: mode == .signIn, ns: ns) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { mode = .signIn; errorMessage = nil }
                            }
                            TabPill(label: "Create account", isActive: mode == .signUp, ns: ns) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { mode = .signUp; errorMessage = nil }
                            }
                        }
                        .padding(4)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)

                        // Role selector (sign up only)
                        if mode == .signUp {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("I AM A")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.white.opacity(0.35))
                                    .tracking(1.5)
                                HStack(spacing: 10) {
                                    RolePill(label: "Doctor", icon: "stethoscope", isSelected: selectedRole == .doctor) {
                                        withAnimation(.spring(response: 0.3)) { selectedRole = .doctor }
                                    }
                                    RolePill(label: "Hospital", icon: "cross.case.fill", isSelected: selectedRole == .hospital) {
                                        withAnimation(.spring(response: 0.3)) { selectedRole = .hospital }
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 20)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // Fields
                        VStack(spacing: 12) {
                            AuthField(icon: "envelope", placeholder: "Email address", text: $email, keyboard: .emailAddress)
                            AuthField(icon: "lock", placeholder: "Password", text: $password, isSecure: true)
                            if mode == .signUp {
                                AuthField(icon: "lock.fill", placeholder: "Confirm password", text: $confirmPassword, isSecure: true)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 24)
                        .animation(.spring(response: 0.35), value: mode)

                        // Error
                        if let err = errorMessage {
                            Text(err)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(hex: "F87171"))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .padding(.top, 12)
                                .transition(.opacity)
                        }

                        // Forgot password (sign in only)
                        if mode == .signIn {
                            HStack {
                                Spacer()
                                Button("Forgot password?") {}
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color(hex: "4F8EF7").opacity(0.8))
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 8)
                        }

                        // Primary CTA
                        Button { handleSubmit() } label: {
                            ZStack {
                                if isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(mode == .signIn ? "Sign in" : "Create account")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "4F8EF7"), Color(hex: "7C3AED")],
                                    startPoint: .leading, endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading || email.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty || (mode == .signUp && confirmPassword.isEmpty))
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                        // Divider
                        HStack(spacing: 12) {
                            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                            Text("OR").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.white.opacity(0.25)).tracking(1)
                            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 20)

                        // Google SSO
                        Button {} label: {
                            HStack(spacing: 10) {
                                Image(systemName: "globe")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.75))
                                Text("Continue with Google")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.white.opacity(0.75))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.horizontal, 20)

                    // Terms
                    Text("By continuing you agree to our Terms of Service and Privacy Policy.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.2))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.top, 24)
                        .padding(.bottom, 48)
                }
            }
        }
        .withContactSupport()
        .sheet(isPresented: $showDevRolePicker) {
            DevRolePickerView(auth: auth)
        }
    }

    #if DEBUG
    /// Short aliases for investor demos. Real auth still goes through Supabase.
    private let demoAccounts: [String: (email: String, role: UserRole)] = [
        "erdunn": ("erdunn706@gmail.com", .hospital),
        "erdunn706@gmail.com": ("erdunn706@gmail.com", .hospital),
        "jdunn": ("jdunn@eporthospine.com", .doctor),
        "jdunn@eporthospine": ("jdunn@eporthospine.com", .doctor),
        "jdunn@eporthospine.com": ("jdunn@eporthospine.com", .doctor)
    ]
    private let demoPassword = "1234567890"
    #endif

    private func normalizeEmail(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        #if DEBUG
        if let mapped = demoAccounts[value]?.email { return mapped }
        #endif
        if value == "erdunn" { return "erdunn706@gmail.com" }
        if value == "jdunn" || value == "jdunn@eporthospine" { return "jdunn@eporthospine.com" }
        if value.hasSuffix("@eporthospine") { return value + ".com" }
        return value
    }

    private func handleSubmit() {
        errorMessage = nil
        let trimmedEmail = normalizeEmail(email)
        guard !trimmedEmail.isEmpty else { errorMessage = "Please enter your email."; return }
        guard password.count >= 6 else { errorMessage = "Password must be at least 6 characters."; return }

        #if DEBUG
        // Keep the old role-picker only for the exact demo password on known accounts.
        if let demo = demoAccounts[trimmedEmail], password == demoPassword,
           !SupabaseAuthService.shared.isConfigured {
            isLoading = true
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run {
                    isLoading = false
                    SessionStore.shared.beginSession(userID: UUID(), email: demo.email, role: demo.role)
                    let hasProfile = demo.role == .doctor ? DoctorProfile.load() != nil : HospitalProfile.load() != nil
                    if hasProfile { auth.completeOnboarding(role: demo.role) } else { auth.selectRole(demo.role) }
                }
            }
            return
        }
        #endif

        if SupabaseAuthService.shared.isConfigured {
            isLoading = true
            Task {
                do {
                    if mode == .signUp {
                        guard password == confirmPassword else {
                            await MainActor.run { isLoading = false; errorMessage = "Passwords don't match." }
                            return
                        }
                        let userID = try await SupabaseAuthService.shared.signUp(email: trimmedEmail, password: password, role: selectedRole)
                        await MainActor.run {
                            isLoading = false
                            SessionStore.shared.beginSession(userID: userID, email: trimmedEmail, role: selectedRole)
                            auth.selectRole(selectedRole)
                        }
                    } else {
                        let (userID, role) = try await SupabaseAuthService.shared.signIn(email: trimmedEmail, password: password)
                        await MainActor.run {
                            isLoading = false
                            SessionStore.shared.beginSession(userID: userID, email: trimmedEmail, role: role)
                            let hasProfile = role == .doctor ? DoctorProfile.load() != nil : HospitalProfile.load() != nil
                            if hasProfile { auth.completeOnboarding(role: role) } else { auth.selectRole(role) }
                        }
                    }
                } catch let urlErr as URLError
                    where [.cannotConnectToHost, .notConnectedToInternet,
                           .networkConnectionLost, .timedOut,
                           .cannotFindHost, .dnsLookupFailed].contains(urlErr.code) {
                    // Server unreachable — fall through to local offline auth
                    await MainActor.run { isLoading = false }
                    handleLocalAuth(trimmedEmail: trimmedEmail)
                } catch {
                    await MainActor.run { isLoading = false; errorMessage = error.localizedDescription }
                }
            }
            return
        }

        handleLocalAuth(trimmedEmail: trimmedEmail)
    }

    // MARK: - Local / offline auth

    private func handleLocalAuth(trimmedEmail: String) {
        if mode == .signUp {
            guard password == confirmPassword else { errorMessage = "Passwords don't match."; return }
            if AccountStore.shared.accountExists(email: trimmedEmail) {
                errorMessage = "Account already exists. Sign in instead."; return
            }
            isLoading = true
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await MainActor.run {
                    isLoading = false
                    let userID = AccountStore.shared.register(email: trimmedEmail, password: password, role: selectedRole)
                    SessionStore.shared.beginSession(userID: userID, email: trimmedEmail, role: selectedRole)
                    auth.selectRole(selectedRole)
                }
            }
        } else {
            // If no local account yet, create one on first offline sign-in so the user isn't blocked
            if !AccountStore.shared.accountExists(email: trimmedEmail) {
                let userID = AccountStore.shared.register(email: trimmedEmail, password: password, role: .doctor)
                SessionStore.shared.beginSession(userID: userID, email: trimmedEmail, role: .doctor)
                auth.selectRole(.doctor)
                return
            }
            guard AccountStore.shared.passwordMatches(email: trimmedEmail, password: password) else {
                errorMessage = "Incorrect password."; return
            }
            isLoading = true
            Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                await MainActor.run {
                    isLoading = false
                    let role = AccountStore.shared.role(for: trimmedEmail) ?? .doctor
                    let userID = AccountStore.shared.userID(for: trimmedEmail) ?? UUID()
                    SessionStore.shared.beginSession(userID: userID, email: trimmedEmail, role: role)
                    let hasProfile = role == .doctor ? DoctorProfile.load() != nil : HospitalProfile.load() != nil
                    if hasProfile { auth.completeOnboarding(role: role) } else { auth.selectRole(role) }
                }
            }
        }
    }
}

// MARK: - Dev Role Picker

private struct DevRolePickerView: View {
    @ObservedObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                BackgroundGradient()
                VStack(spacing: 14) {
                    Text("Dev Login — pick a role").font(.headline).foregroundStyle(.secondary)
                    ForEach(UserRole.allCases) { role in
                        Button {
                            auth.selectRole(role)
                            dismiss()
                        } label: {
                            Label(role.rawValue, systemImage: role == .doctor ? "stethoscope" : "cross.case.fill")
                                .font(.headline).frame(maxWidth: .infinity).padding()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding()
            }
            .navigationTitle("Select Role")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
        }
    }
}

// MARK: - Tab Pill

private struct TabPill: View {
    let label: String; let isActive: Bool; let ns: Namespace.ID; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.4))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                            .matchedGeometryEffect(id: "tab", in: ns)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Role Pill

private struct RolePill: View {
    let label: String; let icon: String; let isSelected: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color(hex: "4F8EF7") : Color.white.opacity(0.4))
                Text(label)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : Color.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? Color(hex: "4F8EF7").opacity(0.15) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(isSelected ? Color(hex: "4F8EF7").opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Auth Field

private struct AuthField: View {
    let icon: String; let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var isSecure: Bool = false
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.3))
                .frame(width: 20)
            Group {
                if isSecure && !isRevealed {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .tint(Color(hex: "4F8EF7"))
            if isSecure {
                Button { isRevealed.toggle() } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Animated Mesh Background

private struct MeshBackground: View {
    var body: some View {
        // Static gradient — animated TimelineView + blur was too expensive on device
        LinearGradient(
            colors: [Color(hex: "0A0F1E"), Color(hex: "1E3A8A").opacity(0.45), Color(hex: "0A0F1E")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - Color hex init

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int & 0xFF)          / 255
        self.init(red: r, green: g, blue: b)
    }
}

#Preview { AuthView(auth: AuthService.shared) }

// MARK: - Account Store (local fallback when Supabase is not configured)

final class AccountStore {
    static let shared = AccountStore()
    private let key = "accounts_v2"

    struct Account: Codable {
        let id: UUID
        let email: String
        let passwordHash: String
        let role: String
    }

    private var accounts: [Account] {
        get {
            guard let d = UserDefaults.standard.data(forKey: key),
                  let a = try? JSONDecoder().decode([Account].self, from: d) else { return migrateFromV1() }
            return a
        }
        set {
            if let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: key) }
        }
    }

    private func migrateFromV1() -> [Account] {
        struct LegacyAccount: Codable { let email: String; let passwordHash: String; let role: String }
        guard let d = UserDefaults.standard.data(forKey: "accounts_v1"),
              let legacy = try? JSONDecoder().decode([LegacyAccount].self, from: d) else { return [] }
        let migrated = legacy.map { Account(id: UUID(), email: $0.email, passwordHash: $0.passwordHash, role: $0.role) }
        accounts = migrated
        return migrated
    }

    func accountExists(email: String) -> Bool {
        accounts.contains { $0.email.lowercased() == email.lowercased() }
    }

    func passwordMatches(email: String, password: String) -> Bool {
        accounts.first { $0.email.lowercased() == email.lowercased() }?.passwordHash == password
    }

    func role(for email: String) -> UserRole? {
        guard let raw = accounts.first(where: { $0.email.lowercased() == email.lowercased() })?.role else { return nil }
        return UserRole(rawValue: raw)
    }

    func userID(for email: String) -> UUID? {
        accounts.first { $0.email.lowercased() == email.lowercased() }?.id
    }

    @discardableResult
    func register(email: String, password: String, role: UserRole) -> UUID {
        let normalized = email.lowercased()
        if let existing = accounts.first(where: { $0.email == normalized }) {
            return existing.id
        }
        let account = Account(id: UUID(), email: normalized, passwordHash: password, role: role.rawValue)
        var all = accounts
        all.append(account)
        accounts = all
        return account.id
    }
}
