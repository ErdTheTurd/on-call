// Shift.swift
// Core shift model supporting per-day default and optional per-hour override.

import Foundation

public struct DoctorShift: Identifiable, Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case scheduled, tradedPending, tradedComplete, canceled }

    public var id: UUID
    public var hospitalID: UUID
    public var doctorID: UUID

    // Per-day primary representation. Use startDate as midnight in hospital timezone.
    public var date: Date

    // Optional hour-based override if policy.granularity == .hour
    public var startTime: Date?
    public var endTime: Date?

    public var status: Status
    public var payRate: Decimal // for penalty calculations

    public init(id: UUID = UUID(), hospitalID: UUID, doctorID: UUID, date: Date, startTime: Date? = nil, endTime: Date? = nil, status: Status = .scheduled, payRate: Decimal = 0) {
        self.id = id
        self.hospitalID = hospitalID
        self.doctorID = doctorID
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.payRate = payRate
    }
}
