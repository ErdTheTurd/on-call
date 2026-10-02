package com.eporthospine.mdshift.data

import com.eporthospine.mdshift.domain.Shift
import com.eporthospine.mdshift.domain.UserRole
import com.eporthospine.mdshift.domain.VerificationStatus
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AuthAndBoardTest {
    @Test
    fun switchingAccountsClearsThePreviousBoard() {
        val book = AccountBook()
        book.prepareForSignIn("user-a")
        book.update { it.copy(board = it.board.copy(shifts = listOf(sampleShift("a"))), doctor = null) }
        book.prepareForSignIn("user-b")
        assertTrue(book.current.board.shifts.isEmpty())
        assertEquals("user-b", book.current.ownerId)
        book.clearOnSignOut()
        assertNull(book.current.ownerId)
        assertNull(book.current.session)
    }

    @Test
    fun passwordSignInRoutesFinishedDoctorPastOnboarding() = runTest {
        val book = AccountBook()
        val api = FakeApi()
        api.doctorComplete = true
        val auth = coordinator(api, book, syncs = mutableListOf())
        auth.signIn("jdunn@eporthospine.com", "secret", UserRole.Doctor)
        val gate = auth.snapshot.value.gate
        assertTrue(gate is AuthGate.Ready)
        assertFalse((gate as AuthGate.Ready).explore)
        assertEquals("doctor-1", book.current.doctor?.userId)
        assertTrue(book.current.doctor!!.isOnboardingComplete)
        assertFalse(book.current.board.explore)
    }

    @Test
    fun unfinishedProfileStaysInOnboarding() = runTest {
        val book = AccountBook()
        val api = FakeApi()
        api.doctorComplete = false
        val auth = coordinator(api, book, syncs = mutableListOf())
        auth.signIn("new@hospital.org", "secret", UserRole.Doctor)
        assertTrue(auth.snapshot.value.gate is AuthGate.NeedsOnboarding)
    }

    @Test
    fun signupCodeThenOptionalMfa() = runTest {
        val book = AccountBook()
        val api = FakeApi()
        api.signupNeedsCode = true
        val auth = coordinator(api, book, syncs = mutableListOf())
        auth.signUp("new@hospital.org", "secret1", "secret1", UserRole.Hospital)
        assertTrue(auth.snapshot.value.gate is AuthGate.EmailCode)
        auth.verifyEmailCode("123456")
        val enroll = auth.snapshot.value.gate
        assertTrue(enroll is AuthGate.MfaEnroll)
        auth.skipEnroll()
        assertTrue(auth.snapshot.value.gate is AuthGate.NeedsOnboarding)
    }

    @Test
    fun enrolledFactorChallengesBeforeTheApp() = runTest {
        val book = AccountBook()
        val api = FakeApi()
        api.totpFactor = "factor-1"
        val auth = coordinator(api, book, syncs = mutableListOf())
        auth.signIn("jdunn@eporthospine.com", "secret", UserRole.Doctor)
        val gate = auth.snapshot.value.gate as AuthGate.MfaChallenge
        assertEquals("factor-1", gate.factorId)
        api.doctorComplete = true
        auth.verifyMfa("654321")
        assertTrue(auth.snapshot.value.gate is AuthGate.Ready)
    }

    @Test
    fun exploreIsRefusedWhenDemoIsOffAndNeverMarksARealSession() = runTest {
        val book = AccountBook()
        val api = FakeApi()
        val auth = AuthCoordinator(api, book, demoEnabled = false, allowNpiBypass = false) {}
        auth.explore(UserRole.Doctor)
        assertTrue(auth.snapshot.value.gate is AuthGate.LoggedOut)
        assertFalse(book.current.board.explore)
        assertTrue(book.current.board.shifts.isEmpty())
    }

    @Test
    fun exploreSeedsNamedRequestsOnlyWithoutAToken() {
        val book = AccountBook()
        val auth = AuthCoordinator(FakeApi(), book, demoEnabled = true, allowNpiBypass = true) {}
        auth.explore(UserRole.Hospital)
        val gate = auth.snapshot.value.gate as AuthGate.Ready
        assertTrue(gate.explore)
        assertNull(book.current.session)
        val names = book.current.board.tokens.map { it.doctorName }
        assertTrue(names.contains("Maya Ellison"))
        assertTrue(names.contains("Luis Ortega"))
        auth.explore(UserRole.Doctor)
        assertEquals("Maya Ellison, MD", book.current.board.trades.first().fromDoctorName)
    }

    @Test
    fun signInAfterExploreDropsSampleData() = runTest {
        val book = AccountBook()
        val api = FakeApi()
        api.doctorComplete = true
        val syncs = mutableListOf<Int>()
        val auth = coordinator(api, book, syncs)
        auth.explore(UserRole.Doctor)
        assertTrue(book.current.board.explore)
        auth.signIn("jdunn@eporthospine.com", "secret", UserRole.Doctor)
        assertFalse(book.current.board.explore)
        assertTrue(book.current.board.shifts.isEmpty() || book.current.board.shifts.none { it.hospitalName == "Average Hospital" && it.id.contains("maya") })
        assertEquals("doctor-1", book.current.session?.userId)
        assertTrue(syncs.isNotEmpty())
    }

    @Test
    fun signOutClearsSessionAndBoard() = runTest {
        val book = AccountBook()
        val api = FakeApi()
        api.doctorComplete = true
        val auth = coordinator(api, book, mutableListOf())
        auth.signIn("a@b.org", "secret", UserRole.Doctor)
        auth.signOut()
        assertTrue(auth.snapshot.value.gate is AuthGate.LoggedOut)
        assertNull(book.current.session)
        assertTrue(book.current.board.shifts.isEmpty())
        assertEquals(1, api.logoutCalls)
    }

    @Test
    fun hospitalApprovalKeepsTheDoctorName() = runTest {
        val book = AccountBook()
        book.prepareForSignIn("hospital-user")
        book.update {
            it.copy(
                session = com.eporthospine.mdshift.domain.StoredSession("hospital-user", "h@b.org", "token", role = "hospital"),
                hospital = com.eporthospine.mdshift.domain.HospitalProfile("hosp", "hospital-user", "Average", "1098765432", "a@b.org"),
                board = DemoBoards.hospital(now = 1_700_000_000_000L).board.copy(explore = false),
            )
        }
        val api = FakeApi()
        val board = ShiftBoard(api, book) { 1_700_000_000_000L }
        val token = book.current.board.tokens.first { it.doctorName == "Maya Ellison" }
        board.setTokenStatus(token, "approved")
        assertEquals("approved", book.current.board.tokens.first { it.id == token.id }.status)
        assertEquals("Maya Ellison", book.current.board.tokens.first { it.id == token.id }.doctorName)
        assertTrue(api.writes.any { it.contains("token_requests") && it.contains("approved") })
    }

    @Test
    fun syncUsesMonthWindowAndDoesNotReplaceOnOverflow() = runTest {
        val book = AccountBook()
        val kept = sampleShift("keep")
        book.update {
            it.copy(
                session = com.eporthospine.mdshift.domain.StoredSession("doctor-1", "a@b.org", "token", role = "doctor"),
                board = it.board.copy(shifts = listOf(kept)),
            )
        }
        val api = FakeApi()
        api.overflow = true
        val board = ShiftBoard(api, book) { java.time.Instant.parse("2026-10-02T00:00:00Z").toEpochMilli() }
        board.sync()
        assertEquals(listOf(kept.id), book.current.board.shifts.map { it.id })
        assertTrue(book.current.board.syncError!!.contains("Nothing was replaced"))
        assertTrue(api.gets.any { it.contains("date=gte.2026-09-24T00:00:00Z") && it.contains("order=date.asc,id.asc") })
    }

    @Test
    fun tradeRequestCarriesCounterAndNames() = runTest {
        val book = AccountBook()
        val seed = DemoBoards.doctor(1_700_000_000_000L)
        book.update {
            it.copy(
                session = com.eporthospine.mdshift.domain.StoredSession(seed.ownerId, "a@b.org", "token", role = "doctor"),
                doctor = seed.doctor,
                board = seed.board.copy(explore = false),
            )
        }
        val api = FakeApi()
        val board = ShiftBoard(api, book) { 1_700_000_000_000L }
        val now = 1_700_000_000_000L
        val partner = book.current.board.roster.first { it.doctorId != seed.ownerId && "Internal Medicine" in it.specialties }
        val shift = book.current.board.shifts.first {
            it.specialty == "Internal Medicine" && it.startEpochMillis > now + 3 * 86_400_000L
        }
        val theirs = book.current.board.shifts.first {
            it.id != shift.id && it.specialty == "Internal Medicine" && it.startEpochMillis > now + 86_400_000L
        }
        board.requestTrade(shift, partner, theirs, 1500.0)
        val body = api.invokes.first { it.first == "request-trade" }.second
        assertTrue(body.contains(partner.displayName))
        assertTrue(body.contains("compensation_amount"))
        assertTrue(body.contains("1000"))
    }

    @Test
    fun directAssignmentInsertIsTheAcceptFallback() = runTest {
        val book = AccountBook()
        val shift = sampleShift("shift-1").copy(startEpochMillis = 1_700_000_000_000L)
        book.update {
            it.copy(
                session = com.eporthospine.mdshift.domain.StoredSession("doctor-1", "a@b.org", "token", role = "doctor"),
                doctor = com.eporthospine.mdshift.domain.DoctorProfile(
                    "doctor-1", "doctor-1", "A", "B", "MD", "1234567890",
                    specialties = listOf("Internal Medicine"),
                    verificationStatus = VerificationStatus.Verified.wire,
                ),
                board = it.board.copy(
                    shifts = listOf(shift),
                    tokens = listOf(
                        com.eporthospine.mdshift.domain.TokenRequest(
                            "t", "doctor-1", shift.hospitalId, "2023-11-14", "approved", "Internal Medicine",
                        ),
                    ),
                ),
            )
        }
        val api = FakeApi()
        api.failAccept = true
        ShiftBoard(api, book) { 1_700_000_000_000L }.acceptShift(shift)
        assertTrue(api.invokes.any { it.first == "accept-shift" })
        assertTrue(api.writes.any { it.contains("rest/v1/assignments") })
    }

    @Test
    fun institutionalEmailRejectsGmail() {
        val result = com.eporthospine.mdshift.domain.verifyHospital(
            "Average Hospital",
            "person@gmail.com",
            com.eporthospine.mdshift.domain.NpiRecord("1", "", "Average Hospital", "", "", "NPI-2", "Average Hospital"),
            null,
        )
        assertFalse(result.emailDomainValid)
        assertEquals(VerificationStatus.Flagged, result.status)
    }

    private fun coordinator(api: FakeApi, book: AccountBook, syncs: MutableList<Int>) =
        AuthCoordinator(api, book, demoEnabled = true, allowNpiBypass = false) { syncs += 1 }

    private fun sampleShift(id: String) = Shift(id, "h", "Average Hospital", "Internal Medicine", 0L, rateFloor = 1100.0)
}

internal class FakeApi : SupabaseApi {
    var signupNeedsCode = false
    var doctorComplete = false
    var totpFactor: String? = null
    var overflow = false
    var failAccept = false
    var logoutCalls = 0
    val gets = mutableListOf<String>()
    val writes = mutableListOf<String>()
    val invokes = mutableListOf<Pair<String, String>>()

    override suspend fun signUp(email: String, password: String, role: UserRole): AuthPayload =
        AuthPayload(if (signupNeedsCode) null else "token", "refresh", "user-1", email, !signupNeedsCode, role.wire, emptyList(), "aal1")

    override suspend fun verifyOtp(email: String, token: String, type: String, accessToken: String?): AuthPayload =
        AuthPayload("token", "refresh", "user-1", email, true, null, emptyList(), "aal1")

    override suspend fun passwordGrant(email: String, password: String): AuthPayload =
        AuthPayload("token", "refresh", "doctor-1", email, true, "doctor", listOfNotNull(totpFactor), "aal1")

    override suspend fun refresh(refreshToken: String) = passwordGrant("a@b.org", "")
    override suspend fun resendSignup(email: String) = Unit
    override suspend fun updateUserEmail(accessToken: String, email: String) = Unit
    override suspend fun enrollTotp(accessToken: String) = TotpEnrollment("enroll-1", "SECRET")
    override suspend fun challengeTotp(accessToken: String, factorId: String) = "challenge"
    override suspend fun verifyTotp(accessToken: String, factorId: String, challengeId: String, code: String) =
        AuthPayload("token-aal2", "refresh", "doctor-1", "jdunn@eporthospine.com", true, "doctor", listOf(factorId), "aal2")

    override suspend fun exchangePkce(code: String, verifier: String) = passwordGrant("a@b.org", "")
    override suspend fun exchangeIdToken(provider: String, idToken: String) = passwordGrant("a@b.org", "")
    override suspend fun logout(accessToken: String, refreshToken: String?) {
        logoutCalls += 1
    }

    override suspend fun restGet(path: String, accessToken: String): String {
        gets += path
        if (overflow && path.contains("shifts")) return List(1000) { """{"id":"$it"}""" }.joinToString(prefix = "[", postfix = "]")
        if (path.contains("profiles?id=")) return """[{"role":"doctor"}]"""
        if (path.contains("doctor_profiles")) {
            val npi = if (doctorComplete) "1234567890" else ""
            val first = if (doctorComplete) "Jordan" else ""
            return """[{"profile_id":"doctor-1","first_name":"$first","last_name":"Dunn","credential":"MD","npi":"$npi","specialties":["Internal Medicine"],"verification_status":"verified","email":"jdunn@eporthospine.com"}]"""
        }
        if (path.contains("hospital_profiles")) return "[]"
        if (path.contains("scheduling_policies")) return "[]"
        return "[]"
    }

    override suspend fun restSend(path: String, method: String, body: String?, accessToken: String, prefer: String?): String {
        writes += "$method $path ${body.orEmpty()}"
        return "[]"
    }

    override suspend fun invoke(name: String, body: String, accessToken: String): String {
        invokes += name to body
        if (name == "accept-shift" && failAccept) throw ApiException("missing", 404)
        return "{}"
    }

    override suspend fun getPublic(url: String) = "{}"
    override fun authorizeUrl(provider: String, redirectTo: String, codeChallenge: String) = "https://example.test/$provider"
}
