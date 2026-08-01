import Foundation

// MARK: - User Role

public enum UserRole: String, CaseIterable, Identifiable, Codable {
    case doctor = "Doctor"
    case hospital = "Hospital"
    public var id: String { rawValue }
}

// MARK: - Verification Status

public enum VerificationStatus: String, Codable, Equatable {
    case unverified = "unverified"
    case pending    = "pending"
    case verified   = "verified"
    case flagged    = "flagged"
    case rejected   = "rejected"

    public var label: String {
        switch self {
        case .unverified: return "Not Verified"
        case .pending:    return "Pending Review"
        case .verified:   return "Verified"
        case .flagged:    return "Needs Review"
        case .rejected:   return "Rejected"
        }
    }

    public var systemImage: String {
        switch self {
        case .unverified: return "questionmark.circle"
        case .pending:    return "clock.badge"
        case .verified:   return "checkmark.seal.fill"
        case .flagged:    return "exclamationmark.triangle.fill"
        case .rejected:   return "xmark.seal.fill"
        }
    }
}
