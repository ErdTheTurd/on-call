package com.eporthospine.mdshift.data

import com.eporthospine.mdshift.domain.Assignment
import com.eporthospine.mdshift.domain.BoardSnapshot
import com.eporthospine.mdshift.domain.DEFAULT_SPECIALTY_RATES
import com.eporthospine.mdshift.domain.DoctorProfile
import com.eporthospine.mdshift.domain.HospitalProfile
import com.eporthospine.mdshift.domain.PenaltyCalculator
import com.eporthospine.mdshift.domain.PenaltyEntry
import com.eporthospine.mdshift.domain.PostgRestPages
import com.eporthospine.mdshift.domain.RosterDoctor
import com.eporthospine.mdshift.domain.SavingsEvent
import com.eporthospine.mdshift.domain.SchedulingAction
import com.eporthospine.mdshift.domain.SchedulingPolicy
import com.eporthospine.mdshift.domain.Shift
import com.eporthospine.mdshift.domain.TokenRequest
import com.eporthospine.mdshift.domain.TradeRequest
import com.eporthospine.mdshift.domain.UserRole
import com.eporthospine.mdshift.domain.VerificationStatus
import com.eporthospine.mdshift.domain.earlyFillSavings
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException

object SyncQueries {
    fun shifts(windowIso: String, hospitalId: String?): String {
        val hospital = hospitalId?.let { "&hospital_id=eq.$it" }.orEmpty()
        return "rest/v1/shifts?select=*&date=gte.$windowIso$hospital&order=date.asc,id.asc"
    }

    fun assignments(windowIso: String, doctorId: String?, hospitalId: String?): String {
        val doctor = doctorId?.let { "&doctor_id=eq.$it" }.orEmpty()
        val hospital = hospitalId?.let { "&shifts.hospital_id=eq.$it" }.orEmpty()
        return "rest/v1/assignments?select=*,shifts!inner(*)" +
            "&shifts.date=gte.$windowIso$doctor$hospital&order=id.asc"
    }

    /**
     * Filled ids for shifts already loaded inside [windowIso].
     * `shift_coverage` exposes shift_id, hospital_id, and is_filled only, so the date
     * window is applied by listing those shift ids instead of reading every filled row.
     */
    fun filled(windowIso: String, shiftIds: List<String>): List<String> {
        require(windowIso.isNotBlank()) { "filled coverage is limited to the sync window" }
        if (shiftIds.isEmpty()) return emptyList()
        return shiftIds.distinct().chunked(80).map { chunk ->
            val list = chunk.joinToString(",")
            "rest/v1/shift_coverage?select=shift_id,is_filled&is_filled=eq.true" +
                "&shift_id=in.($list)&order=shift_id.asc"
        }
    }

    fun tokens(hospitalId: String?, doctorId: String?): String {
        val filters = listOfNotNull(
            hospitalId?.let { "hospital_id=eq.$it" },
            doctorId?.let { "doctor_id=eq.$it" },
        ).joinToString("&")
        val prefix = if (filters.isEmpty()) "" else "$filters&"
        return "rest/v1/token_request_queue?select=*&${prefix}order=requested_at.desc,id.asc"
    }

    fun tokensFallback(hospitalId: String?, doctorId: String?): String =
        tokens(hospitalId, doctorId).replace("token_request_queue", "token_requests")

    fun trades(doctorId: String): String =
        "rest/v1/trade_requests?select=*&or=(from_doctor_id.eq.$doctorId,to_doctor_id.eq.$doctorId)&order=created_at.desc,id.asc"

    fun penalties(hospitalId: String?, doctorId: String?): String {
        val filters = listOfNotNull(
            hospitalId?.let { "hospital_id=eq.$it" },
            doctorId?.let { "doctor_id=eq.$it" },
        ).joinToString("&").let { if (it.isEmpty()) "" else "$it&" }
        return "rest/v1/penalty_ledger?select=*&${filters}order=created_at.desc,id.asc"
    }

    fun roster(hospitalId: String?): String {
        val filter = hospitalId?.let { "hospital_id=eq.$it&" }.orEmpty()
        return "rest/v1/hospital_roster?select=doctor_id,auto_approve,first_name,last_name,credential,specialties,verification_status,hospital_id&${filter}order=doctor_id.asc,hospital_id.asc"
    }

    fun unavailable(hospitalId: String): String =
        "rest/v1/unavailable_days?hospital_id=eq.$hospitalId&select=date&order=date.asc"

    fun savings(hospitalId: String): String =
        "rest/v1/hospital_savings_events?hospital_id=eq.$hospitalId&select=*&order=occurred_at.desc,event_key.asc"
}

data class DemoSeed(
    val ownerId: String,
    val doctor: DoctorProfile?,
    val hospital: HospitalProfile?,
    val board: BoardSnapshot,
)

object DemoIds {
    const val DOCTOR = "00000000-0000-4000-8000-000000009001"
    const val HOSPITAL_USER = "00000000-0000-4000-8000-000000009002"
    const val HOSPITAL = "00000000-0000-4000-8000-000000009010"
    const val MAYA = "00000000-0000-4000-8000-000000009011"
    const val LUIS = "00000000-0000-4000-8000-000000009012"
    const val PRIYA = "00000000-0000-4000-8000-000000009013"
}

object DemoBoards {
    fun doctor(now: Long = System.currentTimeMillis()): DemoSeed {
        val hospital = hospitalProfile()
        val doctor = DoctorProfile(
            id = DemoIds.DOCTOR,
            userId = DemoIds.DOCTOR,
            firstName = "Jordan",
            lastName = "Dunn",
            credential = "MD",
            npi = "1234567893",
            licenseNumber = "A1234567",
            licenseState = "TX",
            specialties = listOf("Internal Medicine"),
            email = "jdunn@eporthospine.com",
            verificationStatus = VerificationStatus.Verified.wire,
        )
        val board = sharedBoard(now)
        val mine = board.shifts.first { it.specialty == "Internal Medicine" }
        val mayaShift = board.shifts.first { it.id.endsWith("maya") }
        return DemoSeed(
            ownerId = DemoIds.DOCTOR,
            doctor = doctor,
            hospital = null,
            board = board.copy(
                explore = true,
                assignments = listOf(
                    Assignment(UUID.randomUUID().toString(), mine.id, DemoIds.DOCTOR, "scheduled", "Jordan Dunn, MD"),
                    Assignment(UUID.randomUUID().toString(), mayaShift.id, DemoIds.MAYA, "scheduled", "Maya Ellison, MD"),
                ),
                trades = listOf(
                    TradeRequest(
                        id = "00000000-0000-4000-8000-0000000090aa",
                        shiftId = mayaShift.id,
                        fromDoctorId = DemoIds.MAYA,
                        toDoctorId = DemoIds.DOCTOR,
                        requestedShiftId = mine.id,
                        compensationAmount = 150.0,
                        state = "pending",
                        fromDoctorName = "Maya Ellison, MD",
                        toDoctorName = "Jordan Dunn, MD",
                        offeredDate = utcDate(mayaShift.startEpochMillis),
                        requestedDate = utcDate(mine.startEpochMillis),
                        specialty = "Internal Medicine",
                    ),
                ),
                tokens = listOf(
                    TokenRequest(
                        id = "00000000-0000-4000-8000-0000000090bb",
                        doctorId = DemoIds.DOCTOR,
                        hospitalId = DemoIds.HOSPITAL,
                        shiftDate = utcDate(now + 3 * DAY),
                        status = "pending",
                        specialty = "Internal Medicine",
                        doctorName = "Jordan Dunn",
                        credential = "MD",
                        hospitalName = "Average Hospital",
                    ),
                ),
            ),
        )
    }

    fun hospital(now: Long = System.currentTimeMillis()): DemoSeed {
        val hospital = hospitalProfile()
        val board = sharedBoard(now)
        val open = board.shifts.filter { it.specialty == "Internal Medicine" }.take(2)
        return DemoSeed(
            ownerId = DemoIds.HOSPITAL_USER,
            doctor = null,
            hospital = hospital,
            board = board.copy(
                explore = true,
                tokens = listOf(
                    TokenRequest(
                        id = "00000000-0000-4000-8000-0000000090c1",
                        doctorId = DemoIds.MAYA,
                        hospitalId = DemoIds.HOSPITAL,
                        shiftDate = utcDate(open[0].startEpochMillis),
                        status = "pending",
                        specialty = "Internal Medicine",
                        doctorName = "Maya Ellison",
                        credential = "MD",
                        hospitalName = "Average Hospital",
                        shiftRate = open[0].rateFloor,
                    ),
                    TokenRequest(
                        id = "00000000-0000-4000-8000-0000000090c2",
                        doctorId = DemoIds.LUIS,
                        hospitalId = DemoIds.HOSPITAL,
                        shiftDate = utcDate(open.getOrElse(1) { open[0] }.startEpochMillis),
                        status = "pending",
                        specialty = "Cardiology",
                        doctorName = "Luis Ortega",
                        credential = "DO",
                        hospitalName = "Average Hospital",
                    ),
                ),
                savings = listOf(
                    SavingsEvent(
                        eventKey = "rate_savings:sample",
                        hospitalId = DemoIds.HOSPITAL,
                        kind = "rate_savings",
                        amount = 420.0,
                        occurredAtEpochMillis = now - DAY,
                        hospitalName = "Average Hospital",
                        specialty = "Internal Medicine",
                    ),
                ),
                penalties = listOf(
                    PenaltyEntry(
                        id = "00000000-0000-4000-8000-0000000090d1",
                        doctorId = DemoIds.PRIYA,
                        hospitalId = DemoIds.HOSPITAL,
                        type = "cancel",
                        amount = 200.0,
                        createdAtEpochMillis = now - 2 * DAY,
                    ),
                ),
            ),
        )
    }

    private fun hospitalProfile() = HospitalProfile(
        id = DemoIds.HOSPITAL,
        userId = DemoIds.HOSPITAL_USER,
        name = "Average Hospital",
        npi = "1098765432",
        email = "admin@averagehospital.org",
        verificationStatus = VerificationStatus.Verified.wire,
        policy = SchedulingPolicy(specialtyBaseRates = DEFAULT_SPECIALTY_RATES, basePenaltyAmount = 100.0),
    )

    private fun sharedBoard(now: Long): BoardSnapshot {
        val start = Instant.ofEpochMilli(now).atZone(ZoneOffset.UTC).toLocalDate().plusDays(1)
        val shifts = (0 until 14).flatMap { offset ->
            val day = start.plusDays(offset.toLong()).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
            listOf(
                Shift(
                    id = "00000000-0000-4000-8000-${1000 + offset}",
                    hospitalId = DemoIds.HOSPITAL,
                    hospitalName = "Average Hospital",
                    specialty = "Internal Medicine",
                    startEpochMillis = day,
                    rateFloor = 1100.0,
                ),
                Shift(
                    id = "00000000-0000-4000-8000-${2000 + offset}maya",
                    hospitalId = DemoIds.HOSPITAL,
                    hospitalName = "Average Hospital",
                    specialty = if (offset % 2 == 0) "Internal Medicine" else "Cardiology",
                    startEpochMillis = day,
                    rateFloor = if (offset % 2 == 0) 1100.0 else 1600.0,
                ),
            )
        }
        return BoardSnapshot(
            shifts = shifts,
            roster = listOf(
                RosterDoctor(DemoIds.DOCTOR, DemoIds.HOSPITAL, false, "Jordan", "Dunn", "MD", listOf("Internal Medicine"), "verified"),
                RosterDoctor(DemoIds.MAYA, DemoIds.HOSPITAL, true, "Maya", "Ellison", "MD", listOf("Internal Medicine"), "verified"),
                RosterDoctor(DemoIds.LUIS, DemoIds.HOSPITAL, false, "Luis", "Ortega", "DO", listOf("Cardiology"), "verified"),
                RosterDoctor(DemoIds.PRIYA, DemoIds.HOSPITAL, false, "Priya", "Shah", "MD", listOf("Hospitalist"), "pending"),
            ),
            policy = SchedulingPolicy(specialtyBaseRates = DEFAULT_SPECIALTY_RATES, basePenaltyAmount = 100.0),
            explore = true,
        )
    }

    private const val DAY = 86_400_000L
}

class ShiftBoard(
    private val api: SupabaseApi,
    private val book: AccountBook,
    private val now: () -> Long = { System.currentTimeMillis() },
) {
    suspend fun sync() = syncOnce(retryAuth = true)

    private suspend fun syncOnce(retryAuth: Boolean) {
        val session = book.current.session ?: return
        if (book.current.board.explore || session.accessToken.isBlank() || !session.emailConfirmed) return
        val generation = book.generation
        val userId = session.userId
        val token = when (SessionRefresher.ensure(api, book, force = false)) {
            RefreshOutcome.Invalid -> {
                if (book.generation == generation && book.current.session?.userId == userId) book.clearOnSignOut()
                return
            }
            RefreshOutcome.Ready, RefreshOutcome.FailedOpen -> book.current.session?.accessToken
        }
        if (token.isNullOrBlank() || book.generation != generation || book.current.session?.userId != userId) return
        try {
            val role = UserRole.fromWire(book.current.session?.role) ?: return
            val window = PostgRestPages.windowStartIso(Instant.ofEpochMilli(now()))
            val hospitalId = book.current.hospital?.id
            val doctorId = if (role == UserRole.Doctor) userId else null
            val shifts = paged(SyncQueries.shifts(window, if (role == UserRole.Hospital) hospitalId else null), token, ::parseShifts)
            val assignments = paged(
                SyncQueries.assignments(window, doctorId, if (role == UserRole.Hospital) hospitalId else null),
                token,
                ::parseAssignments,
            )
            val filled = if (role == UserRole.Doctor) {
                SyncQueries.filled(window, shifts.map { it.id }).flatMap { path ->
                    paged(path, token, ::parseFilledIds)
                }
            } else {
                emptyList()
            }
            if (book.generation != generation || book.current.session?.userId != userId) return
            val kept = book.current.board
            val tokens = pagedTokens(token, if (role == UserRole.Hospital) hospitalId else null, doctorId)
            val trades = if (role == UserRole.Doctor) {
                paged(SyncQueries.trades(userId), token, ::parseTrades)
            } else {
                kept.trades
            }
            val roster = paged(
                SyncQueries.roster(if (role == UserRole.Hospital) hospitalId else null),
                token,
                ::parseRoster,
            )
            val penalties = paged(
                SyncQueries.penalties(if (role == UserRole.Hospital) hospitalId else null, doctorId),
                token,
                ::parsePenalties,
            )
            val unavailable = if (role == UserRole.Hospital && hospitalId != null) {
                paged(SyncQueries.unavailable(hospitalId), token, ::parseUnavailable)
            } else {
                kept.unavailableDays
            }
            val savings = if (role == UserRole.Hospital && hospitalId != null) {
                paged(SyncQueries.savings(hospitalId), token, ::parseSavings)
            } else {
                kept.savings
            }
            val policy = if (role == UserRole.Hospital && hospitalId != null) {
                runCatching {
                    parsePolicy(api.restGet("rest/v1/scheduling_policies?hospital_id=eq.$hospitalId&select=policy", token))
                }.getOrDefault(book.current.hospital?.policy ?: kept.policy)
            } else {
                kept.policy
            }
            book.updateIfOwned(generation, userId) {
                it.copy(
                    board = BoardSnapshot(
                        shifts = shifts,
                        assignments = assignments,
                        tokens = tokens,
                        trades = trades,
                        roster = roster,
                        penalties = penalties,
                        savings = savings,
                        unavailableDays = unavailable,
                        filledShiftIds = filled,
                        policy = policy,
                        explore = false,
                        syncError = null,
                    ),
                )
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: ApiException) {
            if (retryAuth && error.status == 401) {
                when (SessionRefresher.ensure(api, book, force = true)) {
                    RefreshOutcome.Invalid -> {
                        if (book.generation == generation && book.current.session?.userId == userId) book.clearOnSignOut()
                    }
                    RefreshOutcome.Ready -> if (book.generation == generation && book.current.session?.userId == userId) {
                        syncOnce(retryAuth = false)
                    }
                    RefreshOutcome.FailedOpen -> noteSyncFailure(generation, userId, error.message)
                }
                return
            }
            noteSyncFailure(generation, userId, error.message)
        } catch (error: Exception) {
            noteSyncFailure(generation, userId, error.message)
        }
    }

    private fun noteSyncFailure(generation: Long, userId: String, message: String?) {
        book.updateIfOwned(generation, userId) {
            it.copy(board = it.board.copy(syncError = message ?: "We can't reach the server right now."))
        }
    }

    suspend fun requestCoverage(shift: Shift) {
        val session = requireSession()
        val doctor = book.current.doctor
        val date = utcDate(shift.startEpochMillis)
        val policy = book.current.board.policy
        val limit = policy.dailyTokens(session.userId)
        val used = book.current.board.tokens.count { it.doctorId == session.userId && it.shiftDate == date && it.status != "denied" }
        if (used >= limit) throw ApiException("You have used today's request tokens.")
        val auto = book.current.board.roster.any { it.doctorId == session.userId && it.hospitalId == shift.hospitalId && it.autoApprove } ||
            (!policy.administratorApproveShifts && doctor?.verificationStatus == VerificationStatus.Verified.wire)
        val status = if (auto) "auto_approved" else "pending"
        val id = UUID.randomUUID().toString()
        val token = TokenRequest(
            id = id,
            doctorId = session.userId,
            hospitalId = shift.hospitalId,
            shiftDate = date,
            status = status,
            specialty = shift.specialty,
            requestedAtEpochMillis = now(),
            doctorName = doctor?.let { "${it.firstName} ${it.lastName}" }.orEmpty(),
            credential = doctor?.credential.orEmpty(),
            hospitalName = shift.hospitalName,
            shiftRate = shift.rateFloor,
        )
        if (!book.current.board.explore) {
            api.restSend(
                "rest/v1/token_requests",
                "POST",
                buildJsonObject {
                    put("id", id)
                    put("doctor_id", session.userId)
                    put("hospital_id", shift.hospitalId)
                    put("shift_date", date)
                    put("status", status)
                    put("specialty", shift.specialty)
                }.toString(),
                session.accessToken,
                "return=representation",
            )
            runCatching {
                api.restSend(
                    "rest/v1/hospital_doctors?on_conflict=hospital_id,doctor_id",
                    "POST",
                    buildJsonObject {
                        put("hospital_id", shift.hospitalId)
                        put("doctor_id", session.userId)
                        put("auto_approve", false)
                    }.toString(),
                    session.accessToken,
                    "resolution=ignore-duplicates,return=minimal",
                )
            }
        }
        book.update { it.copy(board = it.board.copy(tokens = it.board.tokens + token)) }
    }

    suspend fun acceptShift(shift: Shift) {
        val session = requireSession()
        val date = utcDate(shift.startEpochMillis)
        val approved = book.current.board.tokens.any {
            it.doctorId == session.userId && it.hospitalId == shift.hospitalId && it.shiftDate == date &&
                (it.status == "approved" || it.status == "auto_approved")
        }
        if (!approved) throw ApiException("This day is not approved yet.")
        if (book.current.doctor?.verificationStatus != VerificationStatus.Verified.wire && !book.current.board.explore) {
            throw ApiException("Verification is still pending. You can browse, and accept once you are verified.")
        }
        if (!book.current.board.explore) {
            val payload = buildJsonObject {
                put("shift_id", shift.id)
                put("doctor_id", session.userId)
                put("hospital_id", shift.hospitalId)
                put("shift_date", date)
            }.toString()
            try {
                api.invoke("accept-shift", payload, session.accessToken)
            } catch (error: CancellationException) {
                throw error
            } catch (error: ApiException) {
                if (error.status != 404) throw error
                api.restSend(
                    "rest/v1/assignments",
                    "POST",
                    buildJsonObject {
                        put("shift_id", shift.id)
                        put("doctor_id", session.userId)
                        put("status", "scheduled")
                    }.toString(),
                    session.accessToken,
                    "return=minimal",
                )
            }
            val savings = earlyFillSavings(shift, now())
            if (savings > 0) {
                runCatching {
                    api.restSend(
                        "rest/v1/hospital_savings_events?on_conflict=event_key",
                        "POST",
                        buildJsonObject {
                            put("event_key", "rate_savings:${shift.id}:${session.userId}")
                            put("hospital_id", shift.hospitalId)
                            put("kind", "rate_savings")
                            put("amount", savings)
                            put("occurred_at", toIso(now()))
                            put("source", "android")
                            put("created_by", session.userId)
                            put("hospital_name", shift.hospitalName)
                            put("shift_id", shift.id)
                            put("specialty", shift.specialty)
                        }.toString(),
                        session.accessToken,
                        "resolution=merge-duplicates,return=minimal",
                    )
                }
            }
        }
        val name = book.current.doctor?.displayName.orEmpty()
        book.update {
            it.copy(
                board = it.board.copy(
                    assignments = it.board.assignments + Assignment(UUID.randomUUID().toString(), shift.id, session.userId, "scheduled", name),
                    filledShiftIds = it.board.filledShiftIds + shift.id,
                ),
            )
        }
    }

    suspend fun cancelShift(shift: Shift) {
        val session = requireSession()
        val preview = PenaltyCalculator.preview(SchedulingAction.Cancel, book.current.board.policy, shift.startEpochMillis, now(), shift.rateFloor)
        if (!preview.allowed) throw ApiException("This shift is inside the ${preview.windowHours}-hour cancellation window.")
        if (!book.current.board.explore) {
            val updated = api.restSend(
                "rest/v1/assignments?shift_id=eq.${shift.id}&doctor_id=eq.${session.userId}&status=neq.canceled",
                "PATCH",
                buildJsonObject { put("status", "canceled") }.toString(),
                session.accessToken,
                "return=representation",
            )
            val rows = runCatching { parseArray(updated) }.getOrDefault(emptyList())
            if (rows.isEmpty()) throw ApiException("This shift could not be canceled.")
            if (preview.penaltyAmount > 0) recordPenalty(session.accessToken, session.userId, shift, "cancel", preview.penaltyAmount)
        }
        book.update {
            it.copy(
                board = it.board.copy(
                    assignments = it.board.assignments.map { row ->
                        if (row.shiftId == shift.id && row.doctorId == session.userId) row.copy(status = "canceled") else row
                    },
                ),
            )
        }
    }

    suspend fun requestTrade(shift: Shift, partner: RosterDoctor, theirShift: Shift, compensation: Double) {
        val session = requireSession()
        val amount = compensation.coerceIn(0.0, 1000.0)
        val preview = PenaltyCalculator.preview(SchedulingAction.Trade, book.current.board.policy, shift.startEpochMillis, now())
        if (!preview.allowed) throw ApiException("This shift is inside the ${preview.windowHours}-hour trade window.")
        val me = book.current.doctor?.displayName ?: "You"
        val id = UUID.randomUUID().toString()
        val trade = TradeRequest(
            id = id,
            shiftId = shift.id,
            fromDoctorId = session.userId,
            toDoctorId = partner.doctorId,
            requestedShiftId = theirShift.id,
            compensationAmount = amount,
            state = "pending",
            createdAtEpochMillis = now(),
            fromDoctorName = me,
            toDoctorName = partner.displayName,
            offeredDate = utcDate(shift.startEpochMillis),
            requestedDate = utcDate(theirShift.startEpochMillis),
            specialty = shift.specialty,
        )
        if (!book.current.board.explore) {
            api.invoke(
                "request-trade",
                buildJsonObject {
                    put("id", id)
                    put("shift_id", shift.id)
                    put("from_doctor_id", session.userId)
                    put("to_doctor_id", partner.doctorId)
                    put("requested_shift_id", theirShift.id)
                    put("compensation_amount", amount)
                    put("from_doctor_name", me)
                    put("to_doctor_name", partner.displayName)
                    put("offered_date", utcDate(shift.startEpochMillis))
                    put("requested_date", utcDate(theirShift.startEpochMillis))
                    put("specialty", shift.specialty)
                }.toString(),
                session.accessToken,
            )
        }
        book.update {
            it.copy(
                board = it.board.copy(
                    trades = it.board.trades + trade,
                    assignments = it.board.assignments.map { row ->
                        if (row.shiftId == shift.id) row.copy(status = "traded_pending") else row
                    },
                ),
            )
        }
    }

    suspend fun respondTrade(trade: TradeRequest, accept: Boolean) {
        val session = requireSession()
        if (!book.current.board.explore) {
            api.invoke(
                "respond-trade",
                buildJsonObject {
                    put("trade_id", trade.id)
                    put("accept", accept)
                }.toString(),
                session.accessToken,
            )
        }
        book.update { state ->
            val trades = state.board.trades.map {
                if (it.id == trade.id) it.copy(state = if (accept) "accepted" else "rejected") else it
            }
            val assignments = if (!accept) {
                state.board.assignments.map { if (it.shiftId == trade.shiftId) it.copy(status = "scheduled") else it }
            } else {
                state.board.assignments.map {
                    when (it.shiftId) {
                        trade.shiftId -> it.copy(doctorId = trade.toDoctorId, status = "scheduled", doctorName = trade.toDoctorName)
                        trade.requestedShiftId -> it.copy(doctorId = trade.fromDoctorId, status = "scheduled", doctorName = trade.fromDoctorName)
                        else -> it
                    }
                }
            }
            state.copy(board = state.board.copy(trades = trades, assignments = assignments))
        }
        if (accept) {
            val shift = book.current.board.shifts.firstOrNull { it.id == trade.shiftId }
            if (shift != null) {
                val preview = PenaltyCalculator.preview(SchedulingAction.Trade, book.current.board.policy, shift.startEpochMillis, now())
                if (preview.penaltyAmount > 0 && !book.current.board.explore) {
                    recordPenalty(session.accessToken, trade.fromDoctorId, shift, "trade", preview.penaltyAmount)
                }
            }
        }
    }

    suspend fun counterTrade(parent: TradeRequest, alternate: Shift, compensation: Double) {
        val session = requireSession()
        val amount = compensation.coerceIn(0.0, 1000.0)
        val id = UUID.randomUUID().toString()
        val me = book.current.doctor?.displayName ?: parent.toDoctorName
        val trade = TradeRequest(
            id = id,
            shiftId = alternate.id,
            fromDoctorId = session.userId,
            toDoctorId = parent.fromDoctorId,
            requestedShiftId = parent.shiftId,
            compensationAmount = amount,
            counterOfTradeId = parent.id,
            state = "pending",
            createdAtEpochMillis = now(),
            fromDoctorName = me,
            toDoctorName = parent.fromDoctorName,
            offeredDate = utcDate(alternate.startEpochMillis),
            requestedDate = parent.offeredDate,
            specialty = parent.specialty,
        )
        if (!book.current.board.explore) {
            api.invoke(
                "request-trade",
                buildJsonObject {
                    put("id", id)
                    put("shift_id", alternate.id)
                    put("to_doctor_id", parent.fromDoctorId)
                    put("requested_shift_id", parent.shiftId)
                    put("compensation_amount", amount)
                    put("counter_of_trade_id", parent.id)
                    put("from_doctor_name", me)
                    put("to_doctor_name", parent.fromDoctorName)
                    put("offered_date", utcDate(alternate.startEpochMillis))
                    put("requested_date", parent.offeredDate)
                    put("specialty", parent.specialty)
                }.toString(),
                session.accessToken,
            )
        }
        book.update {
            it.copy(
                board = it.board.copy(
                    trades = it.board.trades.map { row -> if (row.id == parent.id) row.copy(state = "countered") else row } + trade,
                ),
            )
        }
    }

    suspend fun setTokenStatus(token: TokenRequest, status: String) {
        val session = requireSession()
        if (!book.current.board.explore) {
            api.restSend(
                "rest/v1/token_requests?id=eq.${token.id}",
                "PATCH",
                buildJsonObject { put("status", status) }.toString(),
                session.accessToken,
                "return=minimal",
            )
            if (status == "approved" || status == "auto_approved") {
                api.restSend(
                    "rest/v1/hospital_doctors?on_conflict=hospital_id,doctor_id",
                    "POST",
                    buildJsonObject {
                        put("hospital_id", token.hospitalId)
                        put("doctor_id", token.doctorId)
                        put("auto_approve", false)
                    }.toString(),
                    session.accessToken,
                    "resolution=ignore-duplicates,return=minimal",
                )
            }
        }
        book.update {
            it.copy(board = it.board.copy(tokens = it.board.tokens.map { row -> if (row.id == token.id) row.copy(status = status) else row }))
        }
    }

    suspend fun setAutoApprove(doctor: RosterDoctor, enabled: Boolean) {
        val session = requireSession()
        if (!book.current.board.explore) {
            api.restSend(
                "rest/v1/hospital_doctors?hospital_id=eq.${doctor.hospitalId}&doctor_id=eq.${doctor.doctorId}",
                "PATCH",
                buildJsonObject { put("auto_approve", enabled) }.toString(),
                session.accessToken,
                "return=minimal",
            )
        }
        book.update {
            it.copy(
                board = it.board.copy(
                    roster = it.board.roster.map { row ->
                        if (row.doctorId == doctor.doctorId && row.hospitalId == doctor.hospitalId) row.copy(autoApprove = enabled) else row
                    },
                ),
            )
        }
    }

    suspend fun savePolicy(policy: SchedulingPolicy) {
        val hospital = book.current.hospital ?: return
        val session = book.current.session
        if (session != null && !book.current.board.explore) {
            api.restSend(
                "rest/v1/scheduling_policies?on_conflict=hospital_id",
                "POST",
                buildJsonObject {
                    put("hospital_id", hospital.id)
                    put("policy", AppJson.encodeToJsonElement(SchedulingPolicy.serializer(), policy))
                }.toString(),
                session.accessToken,
                "resolution=merge-duplicates,return=minimal",
            )
        }
        book.update {
            it.copy(
                hospital = it.hospital?.copy(policy = policy),
                board = it.board.copy(policy = policy),
            )
        }
    }

    suspend fun postShift(specialty: String, dayEpoch: Long, rateFloor: Double, useAlgorithm: Boolean) {
        val hospital = book.current.hospital ?: return
        val session = book.current.session
        val shift = Shift(
            id = UUID.randomUUID().toString(),
            hospitalId = hospital.id,
            hospitalName = hospital.name,
            specialty = specialty,
            startEpochMillis = dayEpoch,
            rateFloor = rateFloor,
            flatRate = if (useAlgorithm) null else rateFloor,
            usesAlgorithmPricing = useAlgorithm,
        )
        if (session != null && !book.current.board.explore) {
            api.restSend(
                "rest/v1/shifts?on_conflict=id",
                "POST",
                buildJsonObject {
                    put("id", shift.id)
                    put("hospital_id", shift.hospitalId)
                    put("hospital_name", shift.hospitalName)
                    put("specialty", shift.specialty)
                    put("date", toIso(shift.startEpochMillis))
                    put("rate_floor", shift.rateFloor)
                    put("rate_unit", "per_day")
                    put("duration_hours", shift.durationHours)
                    put(
                        "escalation",
                        buildJsonObject {
                            put("type", if (useAlgorithm) "automatic" else "flat")
                            if (!useAlgorithm) put("rate", rateFloor)
                        },
                    )
                }.toString(),
                session.accessToken,
                "resolution=merge-duplicates,return=minimal",
            )
        }
        book.update { it.copy(board = it.board.copy(shifts = it.board.shifts + shift)) }
    }

    suspend fun setUnavailable(date: String, blocked: Boolean) {
        val hospital = book.current.hospital ?: return
        val session = book.current.session
        if (session != null && !book.current.board.explore) {
            if (blocked) {
                api.restSend(
                    "rest/v1/unavailable_days?on_conflict=hospital_id,date",
                    "POST",
                    buildJsonObject {
                        put("hospital_id", hospital.id)
                        put("date", date)
                    }.toString(),
                    session.accessToken,
                    "resolution=merge-duplicates,return=minimal",
                )
            } else {
                api.restSend(
                    "rest/v1/unavailable_days?hospital_id=eq.${hospital.id}&date=eq.$date",
                    "DELETE",
                    null,
                    session.accessToken,
                    "return=minimal",
                )
            }
        }
        book.update {
            val days = if (blocked) (it.board.unavailableDays + date).distinct() else it.board.unavailableDays - date
            it.copy(board = it.board.copy(unavailableDays = days))
        }
    }

    fun clearSyncError() {
        book.update { it.copy(board = it.board.copy(syncError = null)) }
    }

    private suspend fun recordPenalty(token: String, doctorId: String, shift: Shift, type: String, amount: Double) {
        val id = UUID.randomUUID().toString()
        val entry = PenaltyEntry(id, doctorId, shift.hospitalId, shift.id, type, amount, now())
        runCatching {
            api.restSend(
                "rest/v1/penalty_ledger",
                "POST",
                buildJsonObject {
                    put("id", id)
                    put("doctor_id", doctorId)
                    put("hospital_id", shift.hospitalId)
                    put("shift_id", shift.id)
                    put("type", type)
                    put("amount", amount)
                }.toString(),
                token,
                "return=minimal",
            )
        }
        book.update { it.copy(board = it.board.copy(penalties = it.board.penalties + entry)) }
    }

    private suspend fun pagedTokens(token: String, hospitalId: String?, doctorId: String?): List<TokenRequest> =
        try {
            paged(SyncQueries.tokens(hospitalId, doctorId), token, ::parseTokens)
        } catch (error: ApiException) {
            if (error.status == 404 || error.message?.contains("schema cache", ignoreCase = true) == true ||
                error.message?.contains("PGRST205", ignoreCase = true) == true
            ) {
                paged(SyncQueries.tokensFallback(hospitalId, doctorId), token, ::parseTokens)
            } else {
                throw error
            }
        }

    private suspend fun <T> paged(basePath: String, token: String, parse: (String) -> List<T>): List<T> {
        val all = mutableListOf<T>()
        for (page in 0 until PostgRestPages.MAX_PAGES) {
            val body = api.restGet(PostgRestPages.pagePath(basePath, page), token)
            val rows = parse(body)
            all += rows
            if (rows.size < PostgRestPages.PAGE_SIZE) return all
        }
        throw com.eporthospine.mdshift.domain.SyncOverflowException(
            "The server returned more rows than this sync can load. Nothing was replaced.",
        )
    }

    private fun requireSession() = book.current.session ?: throw ApiException("Sign in again.")
}
