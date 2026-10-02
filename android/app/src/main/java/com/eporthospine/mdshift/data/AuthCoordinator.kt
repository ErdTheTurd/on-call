package com.eporthospine.mdshift.data

import com.eporthospine.mdshift.domain.DoctorProfile
import com.eporthospine.mdshift.domain.DoctorVerification
import com.eporthospine.mdshift.domain.HospitalProfile
import com.eporthospine.mdshift.domain.HospitalVerification
import com.eporthospine.mdshift.domain.NpiRecord
import com.eporthospine.mdshift.domain.SchedulingPolicy
import com.eporthospine.mdshift.domain.UserRole
import com.eporthospine.mdshift.domain.debugDoctorBypass
import com.eporthospine.mdshift.domain.demoModeEnabled
import com.eporthospine.mdshift.domain.verifyDoctor
import com.eporthospine.mdshift.domain.verifyHospital
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException

sealed interface AuthGate {
    data object LoggedOut : AuthGate
    data class EmailCode(val email: String, val role: UserRole, val signup: Boolean) : AuthGate
    data class MfaChallenge(val factorId: String, val email: String, val role: UserRole) : AuthGate
    data class MfaEnroll(val factorId: String, val secret: String, val email: String, val role: UserRole) : AuthGate
    data class NeedsOnboarding(val role: UserRole) : AuthGate
    data class Ready(val role: UserRole, val explore: Boolean) : AuthGate
}

data class AuthSnapshot(
    val gate: AuthGate = AuthGate.LoggedOut,
    val busy: Boolean = false,
    val error: String? = null,
    val info: String? = null,
)

class AuthCoordinator(
    private val api: SupabaseApi,
    private val book: AccountBook,
    private val demoEnabled: Boolean,
    private val allowNpiBypass: Boolean,
    private val sync: suspend () -> Unit,
) {
    private val _snapshot = MutableStateFlow(AuthSnapshot())
    val snapshot: StateFlow<AuthSnapshot> = _snapshot.asStateFlow()

    fun restore() {
        val state = book.current
        if (state.board.explore) {
            if (!demoEnabled) {
                book.clearOnSignOut()
                _snapshot.value = AuthSnapshot()
                return
            }
            val role = UserRole.fromWire(state.session?.role) ?: UserRole.fromWire(state.oauthRole) ?: UserRole.Doctor
            _snapshot.value = AuthSnapshot(AuthGate.Ready(role, explore = true))
            return
        }
        val session = state.session
        if (session == null || session.accessToken.isBlank()) {
            _snapshot.value = AuthSnapshot()
            return
        }
        val role = UserRole.fromWire(session.role) ?: UserRole.Doctor
        if (!session.emailConfirmed) {
            _snapshot.value = AuthSnapshot(AuthGate.EmailCode(session.email, role, signup = true))
            return
        }
        val factor = state.pendingFactorId
        if (!factor.isNullOrBlank()) {
            _snapshot.value = AuthSnapshot(AuthGate.MfaChallenge(factor, session.email, role))
            return
        }
        if (jwtClaim(session.accessToken, "aal") == "aal1") {
            _snapshot.value = AuthSnapshot(busy = true)
            return
        }
        val complete = when (role) {
            UserRole.Doctor -> state.doctor?.isOnboardingComplete == true
            UserRole.Hospital -> state.hospital?.isOnboardingComplete == true
        }
        _snapshot.value = AuthSnapshot(
            if (complete) AuthGate.Ready(role, explore = false) else AuthGate.NeedsOnboarding(role),
        )
    }

    /**
     * Cold start: refresh the session, re-read the server profile, and sync before the interval loop.
     * An unconfirmed signup stays on the code screen. Explore is left on the local sample board.
     */
    suspend fun resume() {
        if (book.current.board.explore || book.current.session == null) return
        val session = book.current.session ?: return
        if (!session.emailConfirmed) return
        val generation = book.generation
        val userId = session.userId
        val role = UserRole.fromWire(session.role) ?: UserRole.Doctor
        when (SessionRefresher.ensure(api, book, force = false)) {
            RefreshOutcome.Invalid -> {
                if (still(generation, userId)) signOut()
                return
            }
            RefreshOutcome.Ready, RefreshOutcome.FailedOpen -> Unit
        }
        if (!still(generation, userId)) return
        val current = book.current.session ?: return
        if (requireMfaChallenge(generation, userId, role, current.email)) return
        when (val hydrated = runCatching { hydrate(role, current.email, generation) }.getOrElse { error ->
            if (error is CancellationException) throw error
            if (still(generation, userId)) routeFromLocal(role, error.message)
            return
        }) {
            Hydration.Stale -> return
            is Hydration.NeedsOnboarding -> {
                if (still(generation, userId)) _snapshot.value = AuthSnapshot(AuthGate.NeedsOnboarding(hydrated.role))
                return
            }
            is Hydration.Complete -> {
                if (!still(generation, userId)) return
                book.updateIfOwned(generation, userId) { it.copy(session = it.session?.copy(role = hydrated.role.wire)) }
                runCatching { sync() }.onFailure { error ->
                    if (error is CancellationException) throw error
                    book.updateIfOwned(generation, userId) { state ->
                        state.copy(board = state.board.copy(syncError = error.message))
                    }
                }
                if (still(generation, userId)) {
                    _snapshot.value = AuthSnapshot(AuthGate.Ready(hydrated.role, explore = false))
                }
            }
        }
    }

    suspend fun signUp(email: String, password: String, confirm: String, role: UserRole) {
        val address = email.trim().lowercase()
        if (password.length < 6) return fail("Password must be at least 6 characters.")
        if (password != confirm) return fail("Passwords don't match.")
        guard {
            val payload = api.signUp(address, password, role)
            val needsCode = payload.accessToken == null || !payload.emailConfirmed
            if (payload.accessToken != null && payload.userId != null) {
                persist(payload, address, role, emailConfirmed = payload.emailConfirmed)
                if (payload.emailConfirmed) {
                    upsertProfileRow(payload.userId, address, role, payload.accessToken)
                }
            }
            if (needsCode) {
                _snapshot.value = AuthSnapshot(AuthGate.EmailCode(address, role, signup = true))
            } else {
                afterPrimaryAuth(payload, address, role, suggestEnroll = true)
            }
        }
    }

    suspend fun signIn(email: String, password: String, role: UserRole) {
        val address = email.trim().lowercase()
        guard {
            try {
                val payload = api.passwordGrant(address, password)
                if (!payload.emailConfirmed) {
                    _snapshot.value = AuthSnapshot(
                        gate = AuthGate.EmailCode(address, role, signup = true),
                        error = "Enter the 6-digit code from your email before signing in.",
                    )
                    return@guard
                }
                afterPrimaryAuth(payload, address, role, suggestEnroll = false)
            } catch (error: ApiException) {
                if (error.message?.contains("6-digit code", ignoreCase = true) == true ||
                    error.message?.contains("not confirmed", ignoreCase = true) == true
                ) {
                    _snapshot.value = AuthSnapshot(
                        gate = AuthGate.EmailCode(address, role, signup = true),
                        error = "Enter the 6-digit code from your email before signing in.",
                    )
                } else {
                    throw error
                }
            }
        }
    }

    suspend fun verifyEmailCode(code: String) {
        val gate = _snapshot.value.gate as? AuthGate.EmailCode ?: return fail("Enter the 6-digit code from your email.")
        val digits = code.filter(Char::isDigit)
        if (digits.length != 6) return fail("Enter the 6-digit code from your email.")
        guard {
            val payload = api.verifyOtp(gate.email, digits, "signup", book.current.session?.accessToken)
            afterPrimaryAuth(payload, gate.email, gate.role, suggestEnroll = true)
        }
    }

    suspend fun resendEmailCode() {
        val gate = _snapshot.value.gate as? AuthGate.EmailCode ?: return
        guard {
            api.resendSignup(gate.email)
            _snapshot.value = _snapshot.value.copy(busy = false, info = "New code sent. Check your inbox.", error = null)
        }
    }

    suspend fun verifyMfa(code: String) {
        val gate = _snapshot.value.gate as? AuthGate.MfaChallenge ?: return
        val digits = code.filter(Char::isDigit)
        if (digits.length != 6) return fail("Enter the 6-digit authenticator code.")
        val token = book.current.session?.accessToken ?: return fail("Could not confirm your account. Sign in again.")
        guard {
            val challenge = api.challengeTotp(token, gate.factorId)
            val payload = api.verifyTotp(token, gate.factorId, challenge, digits)
            book.update { it.copy(pendingFactorId = null) }
            val merged = payload.copy(
                accessToken = payload.accessToken ?: token,
                userId = payload.userId ?: book.current.session?.userId,
                email = payload.email ?: gate.email,
            )
            afterPrimaryAuth(merged, gate.email, gate.role, suggestEnroll = false, alreadyChallenged = true)
        }
    }

    suspend fun confirmEnroll(code: String) {
        val gate = _snapshot.value.gate as? AuthGate.MfaEnroll ?: return
        val digits = code.filter(Char::isDigit)
        if (digits.length != 6) return fail("Enter the 6-digit authenticator code.")
        val token = book.current.session?.accessToken ?: return fail("Could not confirm your account. Sign in again.")
        guard {
            val challenge = api.challengeTotp(token, gate.factorId)
            val payload = api.verifyTotp(token, gate.factorId, challenge, digits)
            if (payload.accessToken != null) {
                book.update {
                    it.copy(
                        session = it.session?.copy(
                            accessToken = payload.accessToken,
                            refreshToken = payload.refreshToken ?: it.session.refreshToken,
                        ),
                    )
                }
            }
            finishAuth(gate.role, gate.email)
        }
    }

    suspend fun skipEnroll() {
        val gate = _snapshot.value.gate as? AuthGate.MfaEnroll ?: return
        guard { finishAuth(gate.role, gate.email) }
    }

    fun beginOAuth(provider: String, role: UserRole): String {
        val verifier = Pkce.verifier()
        val challenge = Pkce.challenge(verifier)
        book.update { it.copy(oauthVerifier = verifier, oauthRole = role.wire) }
        return api.authorizeUrl(provider, AppConfig.OAUTH_REDIRECT, challenge)
    }

    suspend fun completeOAuth(redirect: String) {
        val code = redirect.substringAfter("code=", "").substringBefore("&").trim()
        if (code.isBlank()) return fail("Sign-in was cancelled.")
        val verifier = book.current.oauthVerifier ?: return fail("Sign-in was cancelled.")
        val role = UserRole.fromWire(book.current.oauthRole) ?: UserRole.Doctor
        guard {
            val payload = api.exchangePkce(code, verifier)
            book.update { it.copy(oauthVerifier = null) }
            afterPrimaryAuth(payload, payload.email.orEmpty(), role, suggestEnroll = payload.verifiedTotpIds.isEmpty())
        }
    }

    suspend fun signInWithGoogle(idToken: String, role: UserRole) {
        guard {
            val payload = api.exchangeIdToken("google", idToken)
            afterPrimaryAuth(payload, payload.email.orEmpty(), role, suggestEnroll = payload.verifiedTotpIds.isEmpty())
        }
    }

    fun explore(role: UserRole) {
        if (!demoEnabled) {
            fail("Explore is available in debug and internal testing builds.")
            return
        }
        book.invalidate()
        val appearance = book.current.appearance
        val seeded = if (role == UserRole.Doctor) DemoBoards.doctor() else DemoBoards.hospital()
        book.update {
            AccountState(
                ownerId = seeded.ownerId,
                session = null,
                doctor = seeded.doctor,
                hospital = seeded.hospital,
                board = seeded.board,
                appearance = appearance,
                oauthRole = role.wire,
            )
        }
        _snapshot.value = AuthSnapshot(AuthGate.Ready(role, explore = true))
    }

    suspend fun signOut() {
        val session = book.current.session
        if (session != null) {
            runCatching { api.logout(session.accessToken, session.refreshToken) }
        }
        book.clearOnSignOut()
        _snapshot.value = AuthSnapshot()
    }

    fun backToSignIn() {
        book.clearOnSignOut()
        _snapshot.value = AuthSnapshot()
    }

    suspend fun lookupDoctor(
        firstName: String,
        lastName: String,
        credential: String,
        npi: String,
        licenseNumber: String,
        licenseState: String,
        email: String,
        emailFromProvider: Boolean,
    ): DoctorVerification {
        val digits = npi.filter(Char::isDigit)
        val result = if (allowNpiBypass && debugDoctorBypass(npi, licenseNumber, licenseState, email)) {
            verifyDoctor(
                firstName, lastName, credential, email, true,
                NpiRecord(npi, firstName, lastName, credential, "Internal Medicine", "NPI-1", null),
                null,
            )
        } else {
            val record = runCatching { fetchNpi(digits) }.getOrElse { error ->
                return bindDoctor(
                    verifyDoctor(firstName, lastName, credential, email, emailFromProvider, null, error.message),
                    digits, licenseNumber, licenseState,
                )
            }
            if (record.enumerationType != "NPI-1") {
                return bindDoctor(
                    verifyDoctor(
                        firstName, lastName, credential, email, emailFromProvider, null,
                        "That NPI belongs to an organization, not an individual provider.",
                    ),
                    digits, licenseNumber, licenseState,
                )
            }
            verifyDoctor(firstName, lastName, credential, email, emailFromProvider, record, null)
        }
        return bindDoctor(result, digits, licenseNumber, licenseState)
    }

    suspend fun lookupHospital(name: String, npi: String, email: String): HospitalVerification {
        val digits = npi.filter(Char::isDigit)
        val record = runCatching { fetchNpi(digits) }.getOrElse { error ->
            return verifyHospital(name, email, null, error.message).copy(checkedNpi = digits)
        }
        if (record.enumerationType != "NPI-2") {
            return verifyHospital(name, email, null, "That NPI belongs to an individual provider, not a facility.")
                .copy(checkedNpi = digits)
        }
        return verifyHospital(name, email, record, null).copy(checkedNpi = digits)
    }

    suspend fun finishDoctor(profile: DoctorProfile) {
        guard {
            val userId = book.current.session?.userId ?: profile.userId
            val linked = profile.copy(id = userId, userId = userId)
            book.prepareForSignIn(userId)
            val generation = book.generation
            book.update { it.copy(doctor = linked, hospital = null) }
            val token = book.current.session?.accessToken
            if (!token.isNullOrBlank() && linked.isOnboardingComplete) {
                api.restSend(
                    "rest/v1/doctor_profiles?on_conflict=profile_id",
                    "POST",
                    doctorRow(linked).toString(),
                    token,
                    "resolution=merge-duplicates,return=minimal",
                )
                upsertProfileRow(userId, linked.email, UserRole.Doctor, token)
            }
            book.update {
                it.copy(session = it.session?.copy(role = UserRole.Doctor.wire))
            }
            sync()
            if (still(generation, userId)) {
                _snapshot.value = AuthSnapshot(AuthGate.Ready(UserRole.Doctor, explore = false))
            }
        }
    }

    suspend fun sendHospitalCode(email: String, name: String) {
        val token = book.current.session?.accessToken ?: return fail("Sign in again to verify your work email.")
        guard {
            api.invoke(
                "send-notification",
                buildJsonObject {
                    put("action", "send_code")
                    put("email", email.trim().lowercase())
                    put("recipientName", name)
                }.toString(),
                token,
            )
            _snapshot.value = _snapshot.value.copy(busy = false, info = "New code sent. Check your inbox.", error = null)
        }
    }

    suspend fun verifyHospitalCode(email: String, code: String): Boolean {
        val digits = code.filter(Char::isDigit)
        if (digits.length != 6) {
            fail("Enter the 6-digit code from your email.")
            return false
        }
        val token = book.current.session?.accessToken ?: return false
        return try {
            _snapshot.value = _snapshot.value.copy(busy = true, error = null)
            api.invoke(
                "send-notification",
                buildJsonObject {
                    put("action", "verify_code")
                    put("email", email.trim().lowercase())
                    put("code", digits)
                }.toString(),
                token,
            )
            _snapshot.value = _snapshot.value.copy(busy = false)
            true
        } catch (error: Exception) {
            fail(error.message ?: "Enter the 6-digit code from your email.")
            false
        }
    }

    suspend fun finishHospital(profile: HospitalProfile) {
        guard {
            val userId = book.current.session?.userId ?: profile.userId
            val linked = profile.copy(userId = userId)
            book.prepareForSignIn(userId)
            val generation = book.generation
            book.update { it.copy(hospital = linked, doctor = null, board = book.current.board.copy(policy = linked.policy)) }
            val token = book.current.session?.accessToken
            if (!token.isNullOrBlank() && linked.isOnboardingComplete) {
                api.restSend(
                    "rest/v1/hospital_profiles?on_conflict=id",
                    "POST",
                    buildJsonObject {
                        put("id", linked.id)
                        put("profile_id", userId)
                        put("name", linked.name)
                        put("npi", linked.npi)
                        put("verification_status", linked.verificationStatus)
                        put("email", linked.email)
                        put(
                            "verification_flags",
                            JsonArray(linked.verificationFlags.map { JsonPrimitive(it) }),
                        )
                    }.toString(),
                    token,
                    "resolution=merge-duplicates,return=minimal",
                )
                api.restSend(
                    "rest/v1/scheduling_policies?on_conflict=hospital_id",
                    "POST",
                    buildJsonObject {
                        put("hospital_id", linked.id)
                        put("policy", AppJson.encodeToJsonElement(SchedulingPolicy.serializer(), linked.policy))
                    }.toString(),
                    token,
                    "resolution=merge-duplicates,return=minimal",
                )
                api.invoke(
                    "send-notification",
                    buildJsonObject {
                        put("action", "hospital_signup")
                        put("email", linked.email)
                        put("name", linked.name)
                        put("npi", linked.npi)
                    }.toString(),
                    token,
                )
                upsertProfileRow(userId, linked.email, UserRole.Hospital, token)
            }
            book.update { it.copy(session = it.session?.copy(role = UserRole.Hospital.wire)) }
            sync()
            if (still(generation, userId)) {
                _snapshot.value = AuthSnapshot(AuthGate.Ready(UserRole.Hospital, explore = false))
            }
        }
    }

    suspend fun requestEmailChange(email: String) {
        val token = book.current.session?.accessToken ?: return fail("Sign in again.")
        val address = email.trim().lowercase()
        if (!address.contains("@")) return fail("Enter an email address.")
        guard {
            api.updateUserEmail(token, address)
            _snapshot.value = _snapshot.value.copy(busy = false, info = "New code sent. Check your inbox.", error = null)
        }
    }

    suspend fun verifyEmailChange(email: String, code: String): Boolean {
        val digits = code.filter(Char::isDigit)
        if (digits.length != 6) {
            fail("Enter the 6-digit code from your email.")
            return false
        }
        val address = email.trim().lowercase()
        return try {
            val payload = api.verifyOtp(address, digits, "email_change", book.current.session?.accessToken)
            if (payload.accessToken != null && payload.userId != null) {
                book.update {
                    it.copy(
                        session = it.session?.copy(
                            accessToken = payload.accessToken,
                            refreshToken = payload.refreshToken ?: it.session.refreshToken,
                            email = address,
                        ),
                    )
                }
            } else {
                book.update { it.copy(session = it.session?.copy(email = address)) }
            }
            true
        } catch (error: Exception) {
            fail(error.message ?: "Enter the 6-digit code from your email.")
            false
        }
    }

    private suspend fun afterPrimaryAuth(
        payload: AuthPayload,
        emailFallback: String,
        preferredRole: UserRole,
        suggestEnroll: Boolean,
        alreadyChallenged: Boolean = false,
    ) {
        val userId = payload.userId ?: throw ApiException("Unexpected response from the server.")
        val token = payload.accessToken ?: book.current.session?.accessToken
            ?: throw ApiException("Unexpected response from the server.")
        val email = payload.email?.takeIf { it.isNotBlank() } ?: emailFallback
        val challengeFactor = if (
            !alreadyChallenged && payload.verifiedTotpIds.isNotEmpty() &&
            (payload.aal == null || payload.aal == "aal1")
        ) {
            payload.verifiedTotpIds.first()
        } else {
            null
        }
        persist(
            payload.copy(accessToken = token, userId = userId, email = email),
            email,
            preferredRole,
            emailConfirmed = payload.emailConfirmed,
            pendingFactorId = challengeFactor,
        )
        if (challengeFactor != null) {
            _snapshot.value = AuthSnapshot(AuthGate.MfaChallenge(challengeFactor, email, preferredRole))
            return
        }
        if (suggestEnroll && payload.verifiedTotpIds.isEmpty()) {
            val enrollment = runCatching { api.enrollTotp(token) }.getOrNull()
            if (enrollment != null) {
                _snapshot.value = AuthSnapshot(
                    AuthGate.MfaEnroll(enrollment.factorId, enrollment.secret, email, preferredRole),
                )
                return
            }
        }
        finishAuth(preferredRole, email)
    }

    private suspend fun finishAuth(preferredRole: UserRole, email: String) {
        val session = book.current.session ?: throw ApiException("Could not confirm your account. Sign in again.")
        book.prepareForSignIn(session.userId)
        val generation = book.generation
        val userId = session.userId
        if (!still(generation, userId)) return
        when (val hydrated = runCatching { hydrate(preferredRole, email, generation) }.getOrElse { error ->
            if (error is CancellationException) throw error
            if (still(generation, userId)) routeFromLocal(preferredRole, error.message)
            return
        }) {
            Hydration.Stale -> return
            is Hydration.NeedsOnboarding -> {
                if (still(generation, userId)) {
                    _snapshot.value = AuthSnapshot(AuthGate.NeedsOnboarding(hydrated.role))
                }
            }
            is Hydration.Complete -> {
                if (!still(generation, userId)) return
                book.updateIfOwned(generation, userId) { it.copy(session = it.session?.copy(role = hydrated.role.wire)) }
                runCatching { sync() }.onFailure { error ->
                    if (error is CancellationException) throw error
                    book.updateIfOwned(generation, userId) { state ->
                        state.copy(board = state.board.copy(syncError = error.message))
                    }
                }
                if (still(generation, userId)) {
                    _snapshot.value = AuthSnapshot(AuthGate.Ready(hydrated.role, explore = false))
                }
            }
        }
    }

    private suspend fun hydrate(preferred: UserRole, email: String, generation: Long): Hydration {
        val session = book.current.session ?: return Hydration.Stale
        val userId = session.userId
        if (!still(generation, userId)) return Hydration.Stale
        val token = session.accessToken
        val serverRole = runCatching {
            parseRole(api.restGet("rest/v1/profiles?id=eq.$userId&select=role", token))
        }.getOrNull() ?: preferred
        if (!still(generation, userId)) return Hydration.Stale
        return when (serverRole) {
            UserRole.Doctor -> {
                val profile = parseDoctorProfile(
                    api.restGet("rest/v1/doctor_profiles?profile_id=eq.$userId&select=*", token),
                    email,
                ) ?: return if (still(generation, userId)) Hydration.NeedsOnboarding(UserRole.Doctor) else Hydration.Stale
                if (!still(generation, userId)) return Hydration.Stale
                val wrote = book.updateIfOwned(generation, userId) {
                    it.copy(doctor = profile, hospital = null, session = it.session?.copy(role = UserRole.Doctor.wire))
                }
                if (!wrote) return Hydration.Stale
                if (profile.isOnboardingComplete) Hydration.Complete(UserRole.Doctor) else Hydration.NeedsOnboarding(UserRole.Doctor)
            }
            UserRole.Hospital -> {
                val rows = api.restGet("rest/v1/hospital_profiles?profile_id=eq.$userId&select=*", token)
                if (!still(generation, userId)) return Hydration.Stale
                val id = parseArray(rows).firstOrNull()?.text("id")
                    ?: return if (still(generation, userId)) Hydration.NeedsOnboarding(UserRole.Hospital) else Hydration.Stale
                val policy = runCatching {
                    parsePolicy(api.restGet("rest/v1/scheduling_policies?hospital_id=eq.$id&select=policy", token))
                }.getOrDefault(SchedulingPolicy())
                val profile = parseHospitalProfile(rows, policy, email)
                    ?: return if (still(generation, userId)) Hydration.NeedsOnboarding(UserRole.Hospital) else Hydration.Stale
                val wrote = book.updateIfOwned(generation, userId) {
                    it.copy(
                        hospital = profile,
                        doctor = null,
                        board = it.board.copy(policy = profile.policy, explore = false),
                        session = it.session?.copy(role = UserRole.Hospital.wire),
                    )
                }
                if (!wrote) return Hydration.Stale
                if (profile.isOnboardingComplete) Hydration.Complete(UserRole.Hospital) else Hydration.NeedsOnboarding(UserRole.Hospital)
            }
        }
    }

    private fun routeFromLocal(preferred: UserRole, message: String?) {
        val role = UserRole.fromWire(book.current.session?.role) ?: preferred
        val complete = when (role) {
            UserRole.Doctor -> book.current.doctor?.isOnboardingComplete == true
            UserRole.Hospital -> book.current.hospital?.isOnboardingComplete == true
        }
        _snapshot.value = AuthSnapshot(
            gate = if (complete) AuthGate.Ready(role, explore = false) else AuthGate.NeedsOnboarding(role),
            error = message,
        )
    }

    private fun persist(
        payload: AuthPayload,
        email: String,
        role: UserRole,
        emailConfirmed: Boolean = true,
        pendingFactorId: String? = null,
    ) {
        val userId = payload.userId ?: return
        val token = payload.accessToken ?: return
        book.prepareForSignIn(userId)
        book.update {
            it.copy(
                session = com.eporthospine.mdshift.domain.StoredSession(
                    userId = userId,
                    email = email.ifBlank { payload.email.orEmpty() },
                    accessToken = token,
                    refreshToken = payload.refreshToken ?: it.session?.refreshToken,
                    role = role.wire,
                    emailConfirmed = emailConfirmed,
                ),
                pendingFactorId = pendingFactorId,
                board = if (it.board.explore) com.eporthospine.mdshift.domain.BoardSnapshot() else it.board.copy(explore = false),
            )
        }
    }

    /**
     * Same rule as iOS `needsMfaChallenge`: verified TOTP and an aal1 (or missing) access token
     * must challenge before any profile or board read. Returns true when the caller must stop.
     */
    private suspend fun requireMfaChallenge(
        generation: Long,
        userId: String,
        role: UserRole,
        email: String,
    ): Boolean {
        val token = book.current.session?.accessToken ?: return true
        if (jwtClaim(token, "aal") == "aal2") {
            book.updateIfOwned(generation, userId) { it.copy(pendingFactorId = null) }
            return false
        }
        val factors = try {
            verifiedTotpIds(AppJson.parseToJsonElement(api.currentUser(token)).jsonObject)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            if (still(generation, userId)) {
                val pending = book.current.pendingFactorId
                _snapshot.value = if (!pending.isNullOrBlank()) {
                    AuthSnapshot(
                        AuthGate.MfaChallenge(pending, email, role),
                        error = error.message ?: "Couldn't confirm your authenticator. Check your connection.",
                    )
                } else {
                    AuthSnapshot(
                        busy = false,
                        error = error.message ?: "Couldn't confirm your authenticator. Check your connection.",
                    )
                }
            }
            return true
        }
        if (!still(generation, userId)) return true
        if (factors.isEmpty()) {
            book.updateIfOwned(generation, userId) { it.copy(pendingFactorId = null) }
            return false
        }
        val factor = factors.first()
        book.updateIfOwned(generation, userId) { it.copy(pendingFactorId = factor) }
        if (still(generation, userId)) {
            _snapshot.value = AuthSnapshot(AuthGate.MfaChallenge(factor, email, role))
        }
        return true
    }

    private fun still(generation: Long, userId: String): Boolean =
        book.generation == generation && book.current.session?.userId == userId && !book.current.board.explore

    private suspend fun upsertProfileRow(userId: String, email: String, role: UserRole, token: String) {
        runCatching {
            api.restSend(
                "rest/v1/profiles?on_conflict=id",
                "POST",
                buildJsonObject {
                    put("id", userId)
                    put("email", email)
                    put("role", role.wire)
                }.toString(),
                token,
                "resolution=merge-duplicates,return=minimal",
            )
        }
    }

    private suspend fun fetchNpi(npi: String) =
        parseNpi(api.getPublic("https://npiregistry.cms.hhs.gov/api/?number=$npi&version=2.1"), npi)

    private suspend fun guard(block: suspend () -> Unit) {
        _snapshot.value = _snapshot.value.copy(busy = true, error = null, info = null)
        try {
            block()
            if (_snapshot.value.busy) _snapshot.value = _snapshot.value.copy(busy = false)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            _snapshot.value = _snapshot.value.copy(busy = false, error = error.message ?: "Something went wrong.")
        }
    }

    private fun bindDoctor(
        result: DoctorVerification,
        npi: String,
        licenseNumber: String,
        licenseState: String,
    ): DoctorVerification = result.copy(
        checkedNpi = npi,
        checkedLicense = licenseNumber,
        checkedState = licenseState,
    )

    private fun fail(message: String) {
        _snapshot.value = _snapshot.value.copy(busy = false, error = message)
    }

    fun newHospitalId(): String = UUID.randomUUID().toString()

    fun reportExternal(message: String?) {
        if (message.isNullOrBlank()) return
        _snapshot.value = _snapshot.value.copy(busy = false, error = message)
    }
}

private sealed interface Hydration {
    data object Stale : Hydration
    data class NeedsOnboarding(val role: UserRole) : Hydration
    data class Complete(val role: UserRole) : Hydration
}

/** Debug builds and the internal-testing flag. Release store builds stay false. */
fun demoEnabled(debugBuild: Boolean, internalTesting: Boolean): Boolean =
    demoModeEnabled(debugBuild, internalTesting)
