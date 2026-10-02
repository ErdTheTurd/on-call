package com.eporthospine.mdshift.ui

import android.content.Context
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.eporthospine.mdshift.data.AccountBook
import com.eporthospine.mdshift.data.AccountState
import com.eporthospine.mdshift.data.AuthCoordinator
import com.eporthospine.mdshift.data.AuthGate
import com.eporthospine.mdshift.data.ShiftBoard
import com.eporthospine.mdshift.domain.DoctorProfile
import com.eporthospine.mdshift.domain.DoctorVerification
import com.eporthospine.mdshift.domain.HospitalProfile
import com.eporthospine.mdshift.domain.HospitalVerification
import com.eporthospine.mdshift.domain.RosterDoctor
import com.eporthospine.mdshift.domain.SchedulingPolicy
import com.eporthospine.mdshift.domain.Shift
import com.eporthospine.mdshift.domain.TokenRequest
import com.eporthospine.mdshift.domain.TradeRequest
import com.eporthospine.mdshift.domain.UserRole
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class RootViewModel(
    private val auth: AuthCoordinator,
    private val board: ShiftBoard,
    private val book: AccountBook,
    private val demoEnabled: Boolean,
) : ViewModel() {
    val authState = auth.snapshot
    val account = book.state
    private val _doctorCheck = MutableStateFlow<DoctorVerification?>(null)
    val doctorCheck: StateFlow<DoctorVerification?> = _doctorCheck
    private val _hospitalCheck = MutableStateFlow<HospitalVerification?>(null)
    val hospitalCheck: StateFlow<HospitalVerification?> = _hospitalCheck
    private val _hospitalCodeOk = MutableStateFlow(false)
    val hospitalCodeOk: StateFlow<Boolean> = _hospitalCodeOk
    private val _emailChangeOk = MutableStateFlow(false)
    val emailChangeOk: StateFlow<Boolean> = _emailChangeOk
    private val _actionError = MutableStateFlow<String?>(null)
    val actionError: StateFlow<String?> = _actionError
    val showDemo: Boolean = demoEnabled
    val hospitalDraftId: String = auth.newHospitalId()

    init {
        auth.restore()
        viewModelScope.launch {
            while (true) {
                delay(20_000)
                val gate = auth.snapshot.value.gate
                if (gate is AuthGate.Ready && !gate.explore) board.sync()
            }
        }
    }

    fun signIn(email: String, password: String, role: UserRole) = launch { auth.signIn(email, password, role) }
    fun signUp(email: String, password: String, confirm: String, role: UserRole) = launch { auth.signUp(email, password, confirm, role) }
    fun verifyCode(code: String) = launch { auth.verifyEmailCode(code) }
    fun resend() = launch { auth.resendEmailCode() }
    fun verifyMfa(code: String) = launch { auth.verifyMfa(code) }
    fun confirmEnroll(code: String) = launch { auth.confirmEnroll(code) }
    fun skipEnroll() = launch { auth.skipEnroll() }
    fun back() = auth.backToSignIn()
    fun explore(role: UserRole) = auth.explore(role)
    fun appleUrl(role: UserRole): String = auth.beginOAuth("apple", role)
    fun completeOAuth(redirect: String) = launch { auth.completeOAuth(redirect) }
    fun signInWithGoogle(idToken: String, role: UserRole) = launch { auth.signInWithGoogle(idToken, role) }
    fun report(message: String?) = auth.reportExternal(message)
    fun signOut() = launch { auth.signOut() }

    fun lookupDoctor(first: String, last: String, credential: String, npi: String, license: String, state: String, email: String) = launch {
        _doctorCheck.value = auth.lookupDoctor(first, last, credential, npi, license, state, email, email.isNotBlank() && book.current.session?.email == email)
    }

    fun finishDoctor(profile: DoctorProfile) = launch { auth.finishDoctor(profile) }

    fun lookupHospital(name: String, npi: String, email: String) = launch {
        _hospitalCheck.value = auth.lookupHospital(name, npi, email)
    }

    fun requestEmailChange(email: String) = launch { auth.requestEmailChange(email) }
    fun verifyEmailChange(email: String, code: String) = launch { _emailChangeOk.value = auth.verifyEmailChange(email, code) }
    fun sendHospitalCode(email: String, name: String) = launch { auth.sendHospitalCode(email, name) }
    fun verifyHospitalCode(email: String, code: String) = launch { _hospitalCodeOk.value = auth.verifyHospitalCode(email, code) }
    fun finishHospital(profile: HospitalProfile) = launch { auth.finishHospital(profile) }

    fun request(shift: Shift) = act { board.requestCoverage(shift) }
    fun accept(shift: Shift) = act { board.acceptShift(shift) }
    fun cancel(shift: Shift) = act { board.cancelShift(shift) }
    fun trade(shift: Shift, partner: RosterDoctor, theirs: Shift, compensation: Double) = act { board.requestTrade(shift, partner, theirs, compensation) }
    fun respond(trade: TradeRequest, accept: Boolean) = act { board.respondTrade(trade, accept) }
    fun counter(trade: TradeRequest, alternate: Shift, compensation: Double) = act { board.counterTrade(trade, alternate, compensation) }
    fun approve(token: TokenRequest) = act { board.setTokenStatus(token, "approved") }
    fun deny(token: TokenRequest) = act { board.setTokenStatus(token, "denied") }
    fun autoApprove(doctor: RosterDoctor, enabled: Boolean) = act { board.setAutoApprove(doctor, enabled) }
    fun savePolicy(policy: SchedulingPolicy) = act { board.savePolicy(policy) }
    fun postShift(specialty: String, day: Long, rate: Double, algorithm: Boolean) = act { board.postShift(specialty, day, rate, algorithm) }
    fun unavailable(date: String, blocked: Boolean) = act { board.setUnavailable(date, blocked) }
    fun retrySync() = launch { board.clearSyncError(); board.sync() }
    fun appearance(mode: String) = book.update { it.copy(appearance = mode) }
    fun toggleHospital(id: String) = book.update {
        val hidden = if (id in it.hiddenHospitalIds) it.hiddenHospitalIds - id else it.hiddenHospitalIds + id
        it.copy(hiddenHospitalIds = hidden)
    }
    fun notify(newShifts: Boolean, trades: Boolean, approvals: Boolean) = book.update {
        it.copy(notifyNewShifts = newShifts, notifyTrades = trades, notifyApprovals = approvals)
    }
    fun priority(enabled: Boolean) = book.update { it.copy(priorityPosting = enabled) }
    fun autoPay(enabled: Boolean) = book.update { it.copy(autoPayInvoices = enabled) }
    fun tokenLimit(doctorId: String, limit: Int) = launch {
        val policy = book.current.board.policy
        board.savePolicy(policy.copy(doctorTokenLimits = policy.doctorTokenLimits + (doctorId to limit.coerceIn(0, 20))))
    }

    private fun act(block: suspend () -> Unit) = launch {
        _actionError.value = null
        try {
            block()
        } catch (error: Exception) {
            _actionError.value = error.message
        }
    }

    private fun launch(block: suspend () -> Unit) {
        viewModelScope.launch { block() }
    }

    companion object {
        fun factory(auth: AuthCoordinator, board: ShiftBoard, book: AccountBook, demoEnabled: Boolean) =
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T =
                    RootViewModel(auth, board, book, demoEnabled) as T
            }
    }
}

suspend fun googleIdToken(context: Context, webClientId: String): String {
    if (webClientId.isBlank()) {
        throw IllegalStateException("Google sign-in needs a Web client ID. See android/README.md.")
    }
    val manager = CredentialManager.create(context)
    val option = GetGoogleIdOption.Builder()
        .setFilterByAuthorizedAccounts(false)
        .setServerClientId(webClientId)
        .setAutoSelectEnabled(false)
        .build()
    val result = manager.getCredential(context, GetCredentialRequest.Builder().addCredentialOption(option).build())
    return GoogleIdTokenCredential.createFrom(result.credential.data).idToken
}

@Composable
fun MdShiftRoot(
    viewModel: RootViewModel,
    onGoogle: (UserRole) -> Unit,
    onApple: (UserRole) -> Unit,
    onOpenUrl: (String) -> Unit,
) {
    val snapshot by viewModel.authState.collectAsState()
    val account by viewModel.account.collectAsState()
    val doctorCheck by viewModel.doctorCheck.collectAsState()
    val hospitalCheck by viewModel.hospitalCheck.collectAsState()
    val hospitalCodeOk by viewModel.hospitalCodeOk.collectAsState()
    val emailChangeOk by viewModel.emailChangeOk.collectAsState()
    val actionError by viewModel.actionError.collectAsState()
    val privacy = { onOpenUrl(com.eporthospine.mdshift.data.AppConfig.PRIVACY_URL) }
    val support = { onOpenUrl(com.eporthospine.mdshift.data.AppConfig.SUPPORT_URL) }
    when (val gate = snapshot.gate) {
        AuthGate.LoggedOut, is AuthGate.EmailCode, is AuthGate.MfaChallenge, is AuthGate.MfaEnroll -> AuthScreen(
            snapshot = snapshot,
            demoEnabled = viewModel.showDemo,
            onSignIn = viewModel::signIn,
            onSignUp = viewModel::signUp,
            onVerifyCode = viewModel::verifyCode,
            onResend = viewModel::resend,
            onVerifyMfa = viewModel::verifyMfa,
            onConfirmEnroll = viewModel::confirmEnroll,
            onSkipEnroll = viewModel::skipEnroll,
            onBack = viewModel::back,
            onGoogle = onGoogle,
            onApple = onApple,
            onExplore = viewModel::explore,
            onPrivacy = privacy,
        )
        is AuthGate.NeedsOnboarding -> when (gate.role) {
            UserRole.Doctor -> DoctorOnboardingScreen(
                snapshot = snapshot,
                email = account.session?.email.orEmpty(),
                userId = account.session?.userId.orEmpty(),
                onLookup = viewModel::lookupDoctor,
                verification = doctorCheck,
                onRequestEmail = viewModel::requestEmailChange,
                onVerifyEmail = viewModel::verifyEmailChange,
                emailVerified = emailChangeOk,
                onFinish = viewModel::finishDoctor,
            )
            UserRole.Hospital -> HospitalOnboardingScreen(
                snapshot = snapshot,
                email = account.session?.email.orEmpty(),
                userId = account.session?.userId.orEmpty(),
                hospitalId = viewModel.hospitalDraftId,
                onLookup = viewModel::lookupHospital,
                verification = hospitalCheck,
                onSendCode = viewModel::sendHospitalCode,
                onVerifyCode = viewModel::verifyHospitalCode,
                codeVerified = hospitalCodeOk,
                onFinish = viewModel::finishHospital,
            )
        }
        is AuthGate.Ready -> when (gate.role) {
            UserRole.Doctor -> DoctorApp(
                account = account,
                now = System.currentTimeMillis(),
                onSignOut = viewModel::signOut,
                onRequest = viewModel::request,
                onAccept = viewModel::accept,
                onCancel = viewModel::cancel,
                onTrade = viewModel::trade,
                onRespond = viewModel::respond,
                onCounter = viewModel::counter,
                onRetrySync = viewModel::retrySync,
                onAppearance = viewModel::appearance,
                onToggleHospital = viewModel::toggleHospital,
                onNotify = viewModel::notify,
                onPrivacy = privacy,
                onSupport = support,
                message = actionError,
            )
            UserRole.Hospital -> HospitalApp(
                account = account,
                onSignOut = viewModel::signOut,
                onApprove = viewModel::approve,
                onDeny = viewModel::deny,
                onAutoApprove = viewModel::autoApprove,
                onSavePolicy = viewModel::savePolicy,
                onPostShift = viewModel::postShift,
                onUnavailable = viewModel::unavailable,
                onRetrySync = viewModel::retrySync,
                onAppearance = viewModel::appearance,
                onPriority = viewModel::priority,
                onAutoPay = viewModel::autoPay,
                onTokenLimit = viewModel::tokenLimit,
                onPrivacy = privacy,
                onSupport = support,
                message = actionError,
            )
        }
    }
    if (snapshot.busy && snapshot.gate is AuthGate.LoggedOut) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
    }
}
