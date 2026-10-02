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
    private val lock = Any()
    private val _state = MutableStateFlow(initial)
    val state: StateFlow<AccountState> = _state.asStateFlow()

    val current: AccountState get() = _state.value

    /** Bumped on sign-in, sign-out, account switch, and Explore so in-flight sync cannot commit. */
    @Volatile
    var generation: Long = 0
        private set

    fun update(block: (AccountState) -> AccountState) {
        synchronized(lock) {
            _state.value = block(_state.value)
        }
    }

    fun invalidate() {
        synchronized(lock) {
            generation++
        }
    }

    /**
     * Writes only when this generation still belongs to [userId].
     * A sign-out or account switch during a network call returns false and leaves the new state alone.
     */
    fun updateIfOwned(generation: Long, userId: String, block: (AccountState) -> AccountState): Boolean {
        synchronized(lock) {
            val current = _state.value
            if (this.generation != generation || current.session?.userId != userId) return false
            _state.value = block(current)
            return true
        }
    }

    fun prepareForSignIn(userId: String) {
        synchronized(lock) {
            generation++
            val current = _state.value
            _state.value = if (current.ownerId != null && current.ownerId != userId) {
                AccountState(ownerId = userId, appearance = current.appearance)
            } else {
                current.copy(ownerId = userId)
            }
        }
    }

    fun clearOnSignOut() {
        synchronized(lock) {
            generation++
            val appearance = _state.value.appearance
            _state.value = AccountState(appearance = appearance)
        }
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
