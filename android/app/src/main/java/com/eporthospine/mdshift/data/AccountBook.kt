package com.eporthospine.mdshift.data

import com.eporthospine.mdshift.domain.Appearance
import com.eporthospine.mdshift.domain.BoardSnapshot
import com.eporthospine.mdshift.domain.DoctorProfile
import com.eporthospine.mdshift.domain.HospitalProfile
import com.eporthospine.mdshift.domain.StoredSession
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable

@Serializable
data class AccountState(
    val ownerId: String? = null,
    val session: StoredSession? = null,
    val doctor: DoctorProfile? = null,
    val hospital: HospitalProfile? = null,
    val board: BoardSnapshot = BoardSnapshot(),
    val appearance: String = Appearance.System.name,
    val hiddenHospitalIds: List<String> = emptyList(),
    val notifyNewShifts: Boolean = true,
    val notifyTrades: Boolean = true,
    val notifyApprovals: Boolean = true,
    val priorityPosting: Boolean = false,
    val autoPayInvoices: Boolean = false,
    val pendingFactorId: String? = null,
    val oauthVerifier: String? = null,
    val oauthRole: String? = null,
)

/**
 * Per-account cache. Signing in as someone else, or signing out, drops the previous user's board.
 */
class AccountBook(initial: AccountState = AccountState()) {
    private val _state = MutableStateFlow(initial)
    val state: StateFlow<AccountState> = _state.asStateFlow()

    val current: AccountState get() = _state.value

    fun update(block: (AccountState) -> AccountState) {
        _state.value = block(_state.value)
    }

    fun prepareForSignIn(userId: String) {
        val owner = current.ownerId
        if (owner != null && owner != userId) {
            val appearance = current.appearance
            _state.value = AccountState(ownerId = userId, appearance = appearance)
        } else {
            update { it.copy(ownerId = userId) }
        }
    }

    fun clearOnSignOut() {
        val appearance = current.appearance
        _state.value = AccountState(appearance = appearance)
    }
}

interface AccountPersistence {
    fun read(): AccountState
    fun write(state: AccountState)
}

class MemoryPersistence(initial: AccountState = AccountState()) : AccountPersistence {
    var saved: AccountState = initial
    override fun read(): AccountState = saved
    override fun write(state: AccountState) {
        saved = state
    }
}
