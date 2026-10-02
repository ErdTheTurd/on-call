package com.eporthospine.mdshift.domain

import kotlinx.serialization.Serializable

enum class UserRole {
    Doctor,
    Hospital,
    ;

    val wire: String get() = name.lowercase()

    companion object {
        fun fromWire(raw: String?): UserRole? = when (raw?.trim()?.lowercase()) {
            "doctor" -> Doctor
            "hospital" -> Hospital
            else -> null
        }
    }
}

enum class VerificationStatus(val wire: String) {
    Unverified("unverified"),
    Pending("pending"),
    Verified("verified"),
    Flagged("flagged"),
    Rejected("rejected"),
    Waitlisted("waitlisted"),
    ;

    companion object {
        fun fromWire(raw: String?): VerificationStatus =
            entries.firstOrNull { it.wire == raw?.lowercase() } ?: Pending
    }
}

enum class Credential(val wire: String) {
    MD("MD"),
    DO("DO"),
    NP("NP"),
    PA("PA"),
    ;

    companion object {
        fun fromWire(raw: String?): Credential =
            entries.firstOrNull { it.wire.equals(raw?.trim(), ignoreCase = true) } ?: MD
    }
}

enum class Appearance { System, Light, Dark }

@Serializable
data class DoctorProfile(
    val id: String,
    val userId: String,
    val firstName: String,
    val lastName: String,
    val credential: String,
    val npi: String,
    val deaNumber: String = "",
    val licenseNumber: String = "",
    val licenseState: String = "",
    val specialties: List<String> = emptyList(),
    val email: String = "",
    val verificationStatus: String = VerificationStatus.Pending.wire,
    val verificationFlags: List<String> = emptyList(),
    val npiRegistryName: String? = null,
    val npiTaxonomy: String? = null,
) {
    val displayName: String get() = "$firstName $lastName, $credential".trim().trimEnd(',')
    val isOnboardingComplete: Boolean
        get() = firstName.isNotBlank() && lastName.isNotBlank() && npi.filter(Char::isDigit).length == 10
}

@Serializable
data class HospitalProfile(
    val id: String,
    val userId: String,
    val name: String,
    val npi: String,
    val email: String,
    val verificationStatus: String = VerificationStatus.Pending.wire,
    val verificationFlags: List<String> = emptyList(),
    val npiRegistryName: String? = null,
    val policy: SchedulingPolicy = SchedulingPolicy(),
) {
    val isOnboardingComplete: Boolean
        get() = name.isNotBlank() && npi.filter(Char::isDigit).length == 10 && email.contains("@")
}

@Serializable
data class PenaltyBracket(
    val hoursBeforeStart: Int,
    val penaltyPercent: Double,
)

@Serializable
data class SchedulingPolicy(
    val granularity: String = "day",
    val administratorApproveShifts: Boolean = true,
    val cancellationPenaltyScale: List<PenaltyBracket> = listOf(PenaltyBracket(24, 2.0)),
    val tradePenaltyScale: List<PenaltyBracket> = listOf(
        PenaltyBracket(24, 0.25),
        PenaltyBracket(72, 0.1),
        PenaltyBracket(99999, 0.0),
    ),
    val cancelWindowHours: Int = 6,
    val tradeWindowHours: Int = 12,
    val basePenaltyAmount: Double = 0.0,
    val tradePenaltiesEnabled: Boolean = true,
    val tradePenaltyAmount: Double = 250.0,
    val tradePenaltyHoursBeforeStart: Int = 72,
    val specialtyBaseRates: Map<String, Double> = emptyMap(),
    val doctorBaseRates: Map<String, Double> = emptyMap(),
    val useAlgorithmPricingByDefault: Boolean = true,
    val specialtyUsesAlgorithm: Map<String, Boolean> = emptyMap(),
    val defaultDailyTokens: Int = 3,
    val doctorTokenLimits: Map<String, Int> = emptyMap(),
) {
    fun rateFor(specialty: String, doctorId: String? = null): Double {
        doctorId?.let { doctorBaseRates[it] }?.let { return it }
        return specialtyBaseRates[specialty] ?: 500.0
    }

    fun dailyTokens(doctorId: String?): Int {
        val raw = doctorId?.let { doctorTokenLimits[it] } ?: defaultDailyTokens
        return raw.coerceIn(0, 20)
    }
}

@Serializable
data class Shift(
    val id: String,
    val hospitalId: String,
    val hospitalName: String,
    val specialty: String,
    val startEpochMillis: Long,
    val durationHours: Int = 24,
    val rateFloor: Double,
    val perDay: Boolean = true,
    val flatRate: Double? = null,
    val usesAlgorithmPricing: Boolean = true,
)

enum class AssignmentStatus { Scheduled, Canceled, TradedPending, TradedComplete }

@Serializable
data class Assignment(
    val id: String,
    val shiftId: String,
    val doctorId: String,
    val status: String,
    val doctorName: String = "",
)

@Serializable
data class TokenRequest(
    val id: String,
    val doctorId: String,
    val hospitalId: String,
    val shiftDate: String,
    val status: String,
    val specialty: String,
    val requestedAtEpochMillis: Long = 0L,
    val doctorName: String = "",
    val credential: String = "",
    val hospitalName: String = "",
    val shiftRate: Double? = null,
)

@Serializable
data class TradeRequest(
    val id: String,
    val shiftId: String,
    val fromDoctorId: String,
    val toDoctorId: String,
    val requestedShiftId: String? = null,
    val compensationAmount: Double = 0.0,
    val counterOfTradeId: String? = null,
    val state: String = "pending",
    val createdAtEpochMillis: Long = 0L,
    val fromDoctorName: String = "",
    val toDoctorName: String = "",
    val offeredDate: String = "",
    val requestedDate: String = "",
    val specialty: String = "",
)

@Serializable
data class RosterDoctor(
    val doctorId: String,
    val hospitalId: String,
    val autoApprove: Boolean = false,
    val firstName: String = "",
    val lastName: String = "",
    val credential: String = "",
    val specialties: List<String> = emptyList(),
    val verificationStatus: String = VerificationStatus.Pending.wire,
) {
    val displayName: String
        get() = listOf(firstName, lastName).filter { it.isNotBlank() }.joinToString(" ")
            .ifBlank { "Doctor" }
            .let { name -> if (credential.isBlank()) name else "$name, $credential" }
}

@Serializable
data class PenaltyEntry(
    val id: String,
    val doctorId: String,
    val hospitalId: String,
    val shiftId: String? = null,
    val type: String,
    val amount: Double,
    val createdAtEpochMillis: Long = 0L,
)

@Serializable
data class SavingsEvent(
    val eventKey: String,
    val hospitalId: String,
    val kind: String,
    val amount: Double,
    val occurredAtEpochMillis: Long,
    val hospitalName: String = "",
    val shiftId: String? = null,
    val specialty: String = "",
)

@Serializable
data class BoardSnapshot(
    val shifts: List<Shift> = emptyList(),
    val assignments: List<Assignment> = emptyList(),
    val tokens: List<TokenRequest> = emptyList(),
    val trades: List<TradeRequest> = emptyList(),
    val roster: List<RosterDoctor> = emptyList(),
    val penalties: List<PenaltyEntry> = emptyList(),
    val savings: List<SavingsEvent> = emptyList(),
    val unavailableDays: List<String> = emptyList(),
    val filledShiftIds: List<String> = emptyList(),
    val policy: SchedulingPolicy = SchedulingPolicy(),
    val explore: Boolean = false,
    val syncError: String? = null,
)

@Serializable
data class StoredSession(
    val userId: String,
    val email: String,
    val accessToken: String,
    val refreshToken: String? = null,
    val role: String? = null,
    /** False while signup is waiting on the 6-digit code. Missing values from older installs stay signed in. */
    val emailConfirmed: Boolean = true,
)

/** True only for debug builds and the Play internal-testing flag. Release stays off. */
fun demoModeEnabled(debug: Boolean, internalTesting: Boolean): Boolean = debug || internalTesting

/**
 * Explore keeps a local sample board. A real sign-in, including review accounts, uses the server.
 */
fun usesLocalSampleData(demoEnabled: Boolean, accessToken: String?): Boolean =
    demoEnabled && accessToken.isNullOrBlank()

val SPECIALTIES = listOf(
    "Internal Medicine",
    "Emergency Medicine",
    "Cardiology",
    "General Surgery",
    "Orthopedics",
    "Anesthesiology",
    "Radiology",
    "Pediatrics",
    "Neurology",
    "Psychiatry",
    "Ob/Gyn",
    "Hospitalist",
)

val DEFAULT_SPECIALTY_RATES = mapOf(
    "Internal Medicine" to 1100.0,
    "Emergency Medicine" to 1400.0,
    "Cardiology" to 1600.0,
    "Surgery" to 1800.0,
    "General Surgery" to 1800.0,
    "Orthopedics" to 1500.0,
    "Anesthesiology" to 1450.0,
    "Radiology" to 1300.0,
    "Pediatrics" to 1050.0,
    "Neurology" to 1550.0,
    "Psychiatry" to 1000.0,
    "Ob/Gyn" to 1350.0,
    "ENT" to 1250.0,
    "Hospitalist" to 1150.0,
)
