import Foundation
import Combine

// MARK: - Session Store

@MainActor
public final class SessionStore: ObservableObject {
    public static let shared = SessionStore()

    private let currentUserKey = "session_current_user_id"
    private let currentEmailKey = "session_current_email"

    @Published public private(set) var currentUserID: UUID?
    @Published public private(set) var currentEmail: String?
    @Published public private(set) var currentRole: UserRole?

    public var doctorProfile: DoctorProfile? { DoctorProfile.load() }
    public var hospitalProfile: HospitalProfile? { HospitalProfile.load() }

    public var currentDoctorID: UUID {
        doctorProfile?.id ?? currentUserID ?? UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    }

    public var currentHospitalID: UUID? {
        hospitalProfile?.id
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: currentUserKey),
           let id = UUID(uuidString: raw) {
            currentUserID = id
        }
        currentEmail = UserDefaults.standard.string(forKey: currentEmailKey)
        if let raw = UserDefaults.standard.string(forKey: "saved_role"),
           let role = UserRole(rawValue: raw) {
            currentRole = role
        }
    }

    public func beginSession(userID: UUID, email: String, role: UserRole) {
        currentUserID = userID
        currentEmail = email.lowercased()
        currentRole = role
        UserDefaults.standard.set(userID.uuidString, forKey: currentUserKey)
        UserDefaults.standard.set(currentEmail, forKey: currentEmailKey)
    }

    public func endSession() {
        currentUserID = nil
        currentEmail = nil
        currentRole = nil
        UserDefaults.standard.removeObject(forKey: currentUserKey)
        UserDefaults.standard.removeObject(forKey: currentEmailKey)
    }

    public func linkDoctorProfile(_ profile: inout DoctorProfile) {
        if profile.userID == nil { profile.userID = currentUserID }
        if profile.id == UUID(uuidString: "00000000-0000-4000-8000-000000000000") {
            profile.id = UUID()
        }
    }

    public func linkHospitalProfile(_ profile: inout HospitalProfile) {
        if profile.userID == nil { profile.userID = currentUserID }
    }
}
