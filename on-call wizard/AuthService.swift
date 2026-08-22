import Foundation
import Combine
import LocalAuthentication
import SwiftUI

// MARK: - Auth State

enum AuthState: Equatable {
    case loggedOut
    case needsOnboarding(UserRole)
    case locked(UserRole)        // has profile but needs Face ID
    case authenticated(UserRole)

    var isAuthenticated: Bool {
        if case .authenticated = self { return true }
        return false
    }
}

// MARK: - Auth Service

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var state: AuthState = .loggedOut
    @Published var errorMessage: String? = nil

    private let roleKey = "saved_role"

    init() {
        // Restore role if previously logged in
        if let raw = UserDefaults.standard.string(forKey: roleKey),
           let role = UserRole(rawValue: raw) {
            state = .locked(role)
        }
    }

    // MARK: - Role Selection

    func selectRole(_ role: UserRole) {
        let hasDoctor   = DoctorProfile.load() != nil
        let hasHospital = HospitalProfile.load() != nil

        switch role {
        case .doctor:
            state = hasDoctor ? .locked(.doctor) : .needsOnboarding(.doctor)
        case .hospital:
            state = hasHospital ? .locked(.hospital) : .needsOnboarding(.hospital)
        }
    }

    // MARK: - Biometric Auth

    func authenticateWithBiometrics() {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Simulator fallback — just authenticate
            if let role = lockedRole { state = .authenticated(role) }
            return
        }

        let reason = "Verify your identity to access MD Shift"
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, err in
            DispatchQueue.main.async {
                if success {
                    if let role = self.lockedRole {
                        UserDefaults.standard.set(role.rawValue, forKey: self.roleKey)
                        self.state = .authenticated(role)
                    }
                } else {
                    self.errorMessage = err?.localizedDescription ?? "Authentication failed."
                }
            }
        }
    }

    // MARK: - Onboarding Complete

    func completeOnboarding(role: UserRole) {
        UserDefaults.standard.set(role.rawValue, forKey: roleKey)
        state = .authenticated(role)
    }

    // MARK: - Sign Out

    func signOut() {
        UserDefaults.standard.removeObject(forKey: roleKey)
        SessionStore.shared.endSession()
        SupabaseAuthService.shared.signOut()
        state = .loggedOut
        errorMessage = nil
    }

    // MARK: - Helpers

    private var lockedRole: UserRole? {
        if case .locked(let role) = state { return role }
        return nil
    }
}

// MARK: - Lock Screen

struct BiometricLockScreen: View {
    @ObservedObject var auth: AuthService
    let role: UserRole

    var body: some View {
        ZStack {
            BackgroundGradient()
            VStack(spacing: 32) {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "stethoscope.circle.fill")
                        .font(.system(size: 72))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                    Text("MD Shift")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Welcome back")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(spacing: 16) {
                    if let err = auth.errorMessage {
                        Text(err)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Button {
                        auth.errorMessage = nil
                        auth.authenticateWithBiometrics()
                    } label: {
                        Label("Unlock with Face ID", systemImage: "faceid")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 32)

                    Button("Use a different account") {
                        auth.signOut()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .padding(.bottom, 48)
            }
        }
        .onAppear { auth.authenticateWithBiometrics() }
    }
}
