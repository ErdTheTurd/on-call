package com.eporthospine.mdshift.data

import com.eporthospine.mdshift.domain.Assignment
import com.eporthospine.mdshift.domain.Credential
import com.eporthospine.mdshift.domain.DoctorProfile
import com.eporthospine.mdshift.domain.HospitalProfile
import com.eporthospine.mdshift.domain.NpiRecord
import com.eporthospine.mdshift.domain.PenaltyEntry
import com.eporthospine.mdshift.domain.RosterDoctor
import com.eporthospine.mdshift.domain.SavingsEvent
import com.eporthospine.mdshift.domain.SchedulingPolicy
import com.eporthospine.mdshift.domain.Shift
import com.eporthospine.mdshift.domain.TokenRequest
import com.eporthospine.mdshift.domain.TradeRequest
import com.eporthospine.mdshift.domain.UserRole
import com.eporthospine.mdshift.domain.VerificationStatus
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Base64

val AppJson = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
    explicitNulls = false
}

class ApiException(message: String, val status: Int = 0) : Exception(message)

fun JsonObject.text(key: String): String? {
    val value = this[key] ?: return null
    val primitive = value as? JsonPrimitive ?: return null
    if (primitive.contentOrNull == null) return null
    return primitive.content
}

fun JsonObject.double(key: String): Double? =
    (this[key] as? JsonPrimitive)?.doubleOrNull ?: text(key)?.toDoubleOrNull()

fun JsonObject.bool(key: String): Boolean? =
    (this[key] as? JsonPrimitive)?.booleanOrNull

fun JsonObject.strings(key: String): List<String> {
    val value = this[key] ?: return emptyList()
    return runCatching {
        value.jsonArray.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }
    }.getOrDefault(emptyList())
}

fun parseArray(body: String): List<JsonObject> {
    val element = AppJson.parseToJsonElement(body)
    val array = element as? JsonArray ?: throw ApiException("Unexpected response from server.")
    return array.map { it.jsonObject }
}

data class AuthPayload(
    val accessToken: String?,
    val refreshToken: String?,
    val userId: String?,
    val email: String?,
    val emailConfirmed: Boolean,
    val metadataRole: String?,
    val verifiedTotpIds: List<String>,
    val aal: String?,
)

data class TotpEnrollment(val factorId: String, val secret: String)

fun parseAuthPayload(body: String): AuthPayload {
    val json = runCatching { AppJson.parseToJsonElement(body).jsonObject }.getOrNull()
        ?: throw ApiException("Unexpected response from the server.")
    val user = (json["user"] as? JsonObject) ?: json
    val id = user.text("id") ?: json.text("id")
    val confirmed = !user.text("email_confirmed_at").isNullOrBlank() || !user.text("confirmed_at").isNullOrBlank()
    val meta = user["user_metadata"] as? JsonObject
    val access = json.text("access_token")
    return AuthPayload(
        accessToken = access,
        refreshToken = json.text("refresh_token"),
        userId = id,
        email = user.text("email") ?: json.text("email"),
        emailConfirmed = confirmed,
        metadataRole = meta?.text("role"),
        verifiedTotpIds = verifiedTotpIds(user),
        aal = access?.let { jwtClaim(it, "aal") },
    )
}

fun verifiedTotpIds(user: JsonObject): List<String> {
    val factors = user["factors"] as? JsonArray ?: return emptyList()
    return factors.mapNotNull { element ->
        val row = element as? JsonObject ?: return@mapNotNull null
        if (row.text("factor_type") == "totp" && row.text("status") == "verified") row.text("id") else null
    }
}

fun jwtClaim(token: String, key: String): String? {
    val parts = token.split('.')
    if (parts.size < 2) return null
    return runCatching {
        val padded = parts[1].replace('-', '+').replace('_', '/')
            .let { it + "=".repeat((4 - it.length % 4) % 4) }
        val json = AppJson.parseToJsonElement(String(Base64.getDecoder().decode(padded))).jsonObject
        json.text(key)
    }.getOrNull()
}

fun humanizeError(status: Int, body: String): String {
    val json = runCatching { AppJson.parseToJsonElement(body).jsonObject }.getOrNull()
    val raw = json?.text("error_description")
        ?: json?.text("msg")
        ?: json?.text("message")
        ?: json?.text("error")
        ?: body.ifBlank { "HTTP $status" }
    val lower = raw.lowercase()
    return when {
        "audience" in lower || "unacceptable" in lower ->
            "Apple Sign In is not configured for this app. Please try email sign-in."
        "nonce" in lower -> "Apple Sign In could not be verified. Please try again."
        "id token" in lower || "id_token" in lower || "provider is not enabled" in lower ->
            "Sign in with Apple is temporarily unavailable. Try email sign-in, or try again later."
        "email not confirmed" in lower -> "Enter the 6-digit code from your email before signing in."
        else -> raw
    }
}

fun epochMillis(raw: String?): Long {
    if (raw.isNullOrBlank()) return 0L
    val text = raw.trim()
    runCatching { return Instant.parse(text).toEpochMilli() }
    runCatching { return Instant.parse(text.replace(" ", "T").let { if (it.endsWith("Z") || it.contains("+")) it else "${it}Z" }).toEpochMilli() }
    val date = runCatching { LocalDate.parse(text.take(10)) }.getOrNull() ?: return 0L
    return date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
}

fun toIso(epochMillis: Long): String = DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochMilli(epochMillis))

fun utcDate(epochMillis: Long): String =
    Instant.ofEpochMilli(epochMillis).atZone(ZoneOffset.UTC).toLocalDate().toString()

fun parseShifts(body: String): List<Shift> = parseArray(body).mapNotNull { row ->
    val id = row.text("id") ?: return@mapNotNull null
    val escalation = row["escalation"] as? JsonObject
    val flat = if (escalation?.text("type") == "flat") escalation.double("rate") else null
    Shift(
        id = id,
        hospitalId = row.text("hospital_id").orEmpty(),
        hospitalName = row.text("hospital_name").orEmpty(),
        specialty = row.text("specialty").orEmpty(),
        startEpochMillis = epochMillis(row.text("date")),
        durationHours = row.double("duration_hours")?.toInt() ?: 24,
        rateFloor = row.double("rate_floor") ?: 0.0,
        perDay = row.text("rate_unit") != "per_hour",
        flatRate = flat,
        usesAlgorithmPricing = flat == null,
    )
}

fun parseAssignments(body: String): List<Assignment> = parseArray(body).mapNotNull { row ->
    val shiftId = row.text("shift_id") ?: return@mapNotNull null
    Assignment(
        id = row.text("id") ?: shiftId,
        shiftId = shiftId,
        doctorId = row.text("doctor_id").orEmpty(),
        status = row.text("status") ?: "scheduled",
        doctorName = row.text("doctor_name").orEmpty(),
    )
}

fun parseTokens(body: String): List<TokenRequest> = parseArray(body).mapNotNull { row ->
    val id = row.text("id") ?: return@mapNotNull null
    TokenRequest(
        id = id,
        doctorId = row.text("doctor_id").orEmpty(),
        hospitalId = row.text("hospital_id").orEmpty(),
        shiftDate = row.text("shift_date").orEmpty().take(10),
        status = row.text("status") ?: "pending",
        specialty = row.text("specialty").orEmpty(),
        requestedAtEpochMillis = epochMillis(row.text("requested_at")),
        doctorName = row.text("doctor_name").orEmpty(),
        credential = row.text("credential").orEmpty(),
        hospitalName = row.text("hospital_name").orEmpty(),
        shiftRate = row.double("shift_rate"),
    )
}

fun parseTrades(body: String): List<TradeRequest> = parseArray(body).mapNotNull { row ->
    val id = row.text("id") ?: return@mapNotNull null
    TradeRequest(
        id = id,
        shiftId = row.text("shift_id").orEmpty(),
        fromDoctorId = row.text("from_doctor_id").orEmpty(),
        toDoctorId = row.text("to_doctor_id").orEmpty(),
        requestedShiftId = row.text("requested_shift_id"),
        compensationAmount = row.double("compensation_amount") ?: 0.0,
        counterOfTradeId = row.text("counter_of_trade_id"),
        state = row.text("state") ?: "pending",
        createdAtEpochMillis = epochMillis(row.text("created_at")),
        fromDoctorName = row.text("from_doctor_name").orEmpty(),
        toDoctorName = row.text("to_doctor_name").orEmpty(),
        offeredDate = row.text("offered_date").orEmpty(),
        requestedDate = row.text("requested_date").orEmpty(),
        specialty = row.text("specialty").orEmpty(),
    )
}

fun parseRoster(body: String): List<RosterDoctor> = parseArray(body).mapNotNull { row ->
    val id = row.text("doctor_id") ?: return@mapNotNull null
    RosterDoctor(
        doctorId = id,
        hospitalId = row.text("hospital_id").orEmpty(),
        autoApprove = row.bool("auto_approve") == true,
        firstName = row.text("first_name").orEmpty(),
        lastName = row.text("last_name").orEmpty(),
        credential = row.text("credential").orEmpty(),
        specialties = row.strings("specialties"),
        verificationStatus = row.text("verification_status") ?: VerificationStatus.Pending.wire,
    )
}

fun parsePenalties(body: String): List<PenaltyEntry> = parseArray(body).mapNotNull { row ->
    val id = row.text("id") ?: return@mapNotNull null
    PenaltyEntry(
        id = id,
        doctorId = row.text("doctor_id").orEmpty(),
        hospitalId = row.text("hospital_id").orEmpty(),
        shiftId = row.text("shift_id"),
        type = row.text("type") ?: "cancel",
        amount = row.double("amount") ?: 0.0,
        createdAtEpochMillis = epochMillis(row.text("created_at")),
    )
}

fun parseSavings(body: String): List<SavingsEvent> = parseArray(body).mapNotNull { row ->
    val key = row.text("event_key") ?: return@mapNotNull null
    SavingsEvent(
        eventKey = key,
        hospitalId = row.text("hospital_id").orEmpty(),
        kind = row.text("kind").orEmpty(),
        amount = row.double("amount") ?: 0.0,
        occurredAtEpochMillis = epochMillis(row.text("occurred_at")),
        hospitalName = row.text("hospital_name").orEmpty(),
        shiftId = row.text("shift_id"),
        specialty = row.text("specialty").orEmpty(),
    )
}

fun parseUnavailable(body: String): List<String> =
    parseArray(body).mapNotNull { it.text("date")?.take(10) }

fun parseFilledIds(body: String): List<String> =
    parseArray(body).mapNotNull { row ->
        if (row.bool("is_filled") == false) null else row.text("shift_id")
    }

fun parseDoctorProfile(body: String, fallbackEmail: String): DoctorProfile? {
    val row = parseArray(body).firstOrNull() ?: return null
    val id = row.text("profile_id") ?: return null
    return DoctorProfile(
        id = id,
        userId = id,
        firstName = row.text("first_name").orEmpty(),
        lastName = row.text("last_name").orEmpty(),
        credential = Credential.fromWire(row.text("credential")).wire,
        npi = row.text("npi").orEmpty(),
        deaNumber = row.text("dea_number").orEmpty(),
        licenseNumber = row.text("license_number").orEmpty(),
        licenseState = row.text("license_state").orEmpty(),
        specialties = row.strings("specialties"),
        email = row.text("email").takeUnless { it.isNullOrBlank() } ?: fallbackEmail,
        verificationStatus = VerificationStatus.fromWire(row.text("verification_status")).wire,
        verificationFlags = row.strings("verification_flags"),
        npiRegistryName = row.text("npi_registry_name"),
        npiTaxonomy = row.text("npi_taxonomy"),
    )
}

fun parseHospitalProfile(body: String, policy: SchedulingPolicy, fallbackEmail: String): HospitalProfile? {
    val row = parseArray(body).firstOrNull() ?: return null
    val id = row.text("id") ?: return null
    val userId = row.text("profile_id") ?: return null
    return HospitalProfile(
        id = id,
        userId = userId,
        name = row.text("name").orEmpty(),
        npi = row.text("npi").orEmpty(),
        email = row.text("email").takeUnless { it.isNullOrBlank() } ?: fallbackEmail,
        verificationStatus = VerificationStatus.fromWire(row.text("verification_status")).wire,
        verificationFlags = row.strings("verification_flags"),
        npiRegistryName = row.text("npi_registry_name"),
        policy = policy,
    )
}

fun parsePolicy(body: String): SchedulingPolicy {
    val row = parseArray(body).firstOrNull() ?: return SchedulingPolicy()
    val policy = row["policy"] ?: return SchedulingPolicy()
    return runCatching { AppJson.decodeFromJsonElement(SchedulingPolicy.serializer(), policy) }
        .getOrDefault(SchedulingPolicy())
}

fun parseRole(body: String): UserRole? {
    val raw = parseArray(body).firstOrNull()?.text("role") ?: return null
    return UserRole.fromWire(raw)
}

fun doctorRow(profile: DoctorProfile): JsonObject = buildJsonObject {
    put("profile_id", profile.userId)
    put("first_name", profile.firstName)
    put("last_name", profile.lastName)
    put("credential", profile.credential)
    put("npi", profile.npi)
    put("specialties", AppJson.parseToJsonElement(AppJson.encodeToString(kotlinx.serialization.builtins.ListSerializer(kotlinx.serialization.serializer<String>()), profile.specialties)))
    put("verification_status", profile.verificationStatus)
    put("dea_number", profile.deaNumber)
    put("license_number", profile.licenseNumber)
    put("license_state", profile.licenseState)
    put("email", profile.email)
    put("verification_flags", AppJson.parseToJsonElement(AppJson.encodeToString(kotlinx.serialization.builtins.ListSerializer(kotlinx.serialization.serializer<String>()), profile.verificationFlags)))
}

fun parseNpi(body: String, npi: String): NpiRecord {
    val json = runCatching { AppJson.parseToJsonElement(body).jsonObject }.getOrNull()
        ?: throw ApiException("Unexpected response from NPI registry.")
    val first = (json["results"] as? JsonArray)?.firstOrNull()?.jsonObject
        ?: throw ApiException("No provider found with that NPI number.")
    val enumType = first.text("enumeration_type").orEmpty()
    val basic = first["basic"] as? JsonObject ?: throw ApiException("Unexpected response from NPI registry.")
    val taxonomy = (first["taxonomies"] as? JsonArray)?.firstOrNull()?.jsonObject?.text("desc").orEmpty()
    return when (enumType) {
        "NPI-1" -> NpiRecord(
            npi = npi,
            firstName = basic.text("first_name").orEmpty(),
            lastName = basic.text("last_name").orEmpty(),
            credential = basic.text("credential").orEmpty(),
            taxonomy = taxonomy,
            enumerationType = "NPI-1",
            organizationName = null,
        )
        "NPI-2" -> {
            val org = basic.text("organization_name").orEmpty()
            NpiRecord(npi, "", org, "", taxonomy, "NPI-2", org)
        }
        else -> throw ApiException("Unexpected response from NPI registry.")
    }
}
