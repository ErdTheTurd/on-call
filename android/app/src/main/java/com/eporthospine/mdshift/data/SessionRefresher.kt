package com.eporthospine.mdshift.data

import kotlin.coroutines.cancellation.CancellationException

enum class RefreshOutcome {
    Ready,
    FailedOpen,
    Invalid,
}

/**
 * Exchanges a stored refresh token when the access token is close to expiry.
 * A network failure keeps the current token. An rejected refresh signs the caller out.
 */
object SessionRefresher {
    suspend fun ensure(api: SupabaseApi, book: AccountBook, force: Boolean): RefreshOutcome {
        val session = book.current.session ?: return RefreshOutcome.Invalid
        if (session.accessToken.isBlank()) return RefreshOutcome.Invalid
        val exp = jwtClaim(session.accessToken, "exp")?.toLongOrNull()
        val now = System.currentTimeMillis() / 1000
        val fresh = exp != null && exp > now + 90
        if (!force && fresh) return RefreshOutcome.Ready
        val refresh = session.refreshToken?.takeIf { it.isNotBlank() }
        if (refresh == null) {
            return if (exp != null && exp <= now) RefreshOutcome.Invalid else RefreshOutcome.Ready
        }
        if (!force && exp == null) return RefreshOutcome.Ready
        val generation = book.generation
        val userId = session.userId
        return try {
            val payload = api.refresh(refresh)
            if (book.generation != generation || book.current.session?.userId != userId) {
                RefreshOutcome.Invalid
            } else {
                val access = payload.accessToken
                if (access.isNullOrBlank()) {
                    RefreshOutcome.FailedOpen
                } else {
                    book.updateIfOwned(generation, userId) {
                        it.copy(
                            session = it.session?.copy(
                                accessToken = access,
                                refreshToken = payload.refreshToken ?: it.session.refreshToken,
                                emailConfirmed = true,
                            ),
                        )
                    }
                    RefreshOutcome.Ready
                }
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: ApiException) {
            if (error.status == 400 || error.status == 401 || error.status == 403) {
                RefreshOutcome.Invalid
            } else {
                RefreshOutcome.FailedOpen
            }
        } catch (_: Exception) {
            RefreshOutcome.FailedOpen
        }
    }
}
