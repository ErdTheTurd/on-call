import Foundation
import Combine
import SwiftUI

// MARK: - Token Store (per doctor, per day)

@MainActor
public final class TokenStore: ObservableObject {
    public static let shared = TokenStore()

    private let storageKey = "doctor_tokens_v2"
    private let defaultDailyTokens = 3

    @Published public var tokensRemaining: Int = 3
    @Published public var dailyLimit: Int = 3
    @Published public var requestedDays: [TokenRequest] = []

    public struct TokenRequest: Identifiable, Codable, Equatable {
        public let id: UUID
        public let doctorID: UUID
        public let doctorName: String
        public let credential: String
        public let hospitalID: UUID
        public let date: Date
        public var status: RequestStatus
        public let hospitalName: String
        public let specialty: String
        public let requestedAt: Date
        public var approvedAt: Date?
        public var shiftRate: Double?

        public enum RequestStatus: String, Codable {
            case pending   = "pending"
            case approved  = "approved"
            case denied    = "denied"
            case autoApproved = "auto_approved"
        }

        public var statusLabel: String {
            switch status {
            case .pending:      return "Pending"
            case .approved:     return "Admin Approved"
            case .denied:       return "Denied"
            case .autoApproved: return "Auto-Approved"
            }
        }

        public var statusColor: String {
            switch status {
            case .pending:      return "orange"
            case .approved:     return "green"
            case .denied:       return "red"
            case .autoApproved: return "blue"
            }
        }

        public init(
            id: UUID = UUID(),
            doctorID: UUID,
            doctorName: String,
            credential: String,
            hospitalID: UUID,
            date: Date,
            status: RequestStatus,
            hospitalName: String,
            specialty: String,
            requestedAt: Date = Date(),
            approvedAt: Date? = nil,
            shiftRate: Double? = nil
        ) {
            self.id = id
            self.doctorID = doctorID
            self.doctorName = doctorName
            self.credential = credential
            self.hospitalID = hospitalID
            self.date = date
            self.status = status
            self.hospitalName = hospitalName
            self.specialty = specialty
            self.requestedAt = requestedAt
            self.approvedAt = approvedAt
            self.shiftRate = shiftRate
        }
    }

    private struct Stored: Codable {
        var tokensRemaining: Int
        var dailyLimit: Int
        var lastResetDate: Date
        var requestedDays: [TokenRequest]
    }

    public init() { load() }

    // MARK: - Request a day

    @discardableResult
    public func requestDay(
        date: Date,
        hospitalID: UUID,
        hospital: String,
        specialty: String,
        doctor: DoctorProfile,
        shiftRate: Double? = nil
    ) -> Bool {
        guard tokensRemaining > 0 else { return false }
        guard !requestedDays.contains(where: {
            Calendar.current.isDate($0.date, inSameDayAs: date) && $0.doctorID == doctor.id
        }) else { return false }

        var status: TokenRequest.RequestStatus = .pending
        var approvedAt: Date? = nil
        let policy = SchedulingPolicyStore.shared.policy(for: hospitalID)

        if !policy.administratorApproveShifts, doctor.verificationStatus == .verified {
            status = .autoApproved
            approvedAt = Date()
        } else if DoctorRosterStore.shared.isAutoApproved(doctorID: doctor.id) {
            status = .autoApproved
            approvedAt = Date()
        }

        let req = TokenRequest(
            id: UUID(),
            doctorID: doctor.id,
            doctorName: "\(doctor.firstName) \(doctor.lastName)",
            credential: doctor.credential.rawValue,
            hospitalID: hospitalID,
            date: date,
            status: status,
            hospitalName: hospital,
            specialty: specialty,
            requestedAt: Date(),
            approvedAt: approvedAt,
            shiftRate: shiftRate
        )
        requestedDays.append(req)
        if status != .autoApproved { tokensRemaining -= 1 }
        save()
        Task { try? await Repositories.tokens.submit(req) }
        return true
    }

    public func approve(id: UUID) {
        guard let idx = requestedDays.firstIndex(where: { $0.id == id }) else { return }
        requestedDays[idx].status = .approved
        requestedDays[idx].approvedAt = Date()
        save()
        Task { try? await Repositories.tokens.updateStatus(id: id, status: .approved) }
    }

    public func deny(id: UUID) {
        guard let idx = requestedDays.firstIndex(where: { $0.id == id }) else { return }
        if requestedDays[idx].status == .pending {
            tokensRemaining = min(tokensRemaining + 1, dailyLimit)
        }
        requestedDays[idx].status = .denied
        save()
        Task { try? await Repositories.tokens.updateStatus(id: id, status: .denied) }
    }

    public func autoApprovePending(forDoctorID doctorID: UUID) {
        var changed = false
        for idx in requestedDays.indices where requestedDays[idx].doctorID == doctorID && requestedDays[idx].status == .pending {
            requestedDays[idx].status = .autoApproved
            requestedDays[idx].approvedAt = Date()
            tokensRemaining = min(tokensRemaining + 1, dailyLimit)
            changed = true
        }
        if changed { save() }
    }

    public func pendingRequests(forHospitalID hospitalID: UUID) -> [TokenRequest] {
        requestedDays.filter { $0.hospitalID == hospitalID }
    }

    public func requests(forHospitalID hospitalID: UUID, on date: Date) -> [TokenRequest] {
        requestedDays.filter {
            $0.hospitalID == hospitalID &&
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }
    }

    public func canAcceptShift(on date: Date, hospitalID: UUID, doctorID: UUID) -> Bool {
        guard let req = requestedDays.first(where: {
            $0.doctorID == doctorID &&
            $0.hospitalID == hospitalID &&
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }) else { return false }
        switch req.status {
        case .approved, .autoApproved: return true
        case .pending, .denied: return false
        }
    }

    // MARK: - Cancel a request

    public func cancelRequest(id: UUID) {
        if let idx = requestedDays.firstIndex(where: { $0.id == id }),
           requestedDays[idx].status == .pending {
            requestedDays.remove(at: idx)
            tokensRemaining = min(tokensRemaining + 1, dailyLimit)
            save()
        }
    }

    public func requestStatus(for date: Date, doctorID: UUID? = nil) -> TokenRequest? {
        let docID = doctorID ?? SessionStore.shared.currentDoctorID
        return requestedDays.first {
            $0.doctorID == docID && Calendar.current.isDate($0.date, inSameDayAs: date)
        }
    }

    /// Merge remote Supabase token rows into local storage (idempotent by id).
    public func mergeRemote(_ remote: [TokenRequest]) {
        var changed = false
        for req in remote {
            if let idx = requestedDays.firstIndex(where: { $0.id == req.id }) {
                if requestedDays[idx].status != req.status {
                    requestedDays[idx].status = req.status
                    requestedDays[idx].approvedAt = req.approvedAt
                    changed = true
                }
            } else {
                requestedDays.append(req)
                changed = true
            }
        }
        if changed { save() }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            tokensRemaining = defaultDailyTokens
            dailyLimit = defaultDailyTokens
            return
        }
        dailyLimit = stored.dailyLimit
        requestedDays = stored.requestedDays
        if Calendar.current.isDateInToday(stored.lastResetDate) {
            tokensRemaining = stored.tokensRemaining
        } else {
            tokensRemaining = stored.dailyLimit
        }
    }

    private func save() {
        let stored = Stored(
            tokensRemaining: tokensRemaining,
            dailyLimit: dailyLimit,
            lastResetDate: Date(),
            requestedDays: requestedDays
        )
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Token Badge View

public struct TokenBadge: View {
    @ObservedObject var store: TokenStore

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<store.dailyLimit, id: \.self) { i in
                Circle()
                    .fill(i < store.tokensRemaining ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(width: 10, height: 10)
                    .animation(.spring(response: 0.3), value: store.tokensRemaining)
            }
            Text("\(store.tokensRemaining)/\(store.dailyLimit) tokens")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.08), in: Capsule())
    }
}
