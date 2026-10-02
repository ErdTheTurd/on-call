package com.eporthospine.mdshift.domain

import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * Pages PostgREST lists in chunks the server will actually return.
 * Live max_rows is 1000, and a request for more is silently truncated.
 */
object PostgRestPages {
    const val PAGE_SIZE = 1000
    const val MAX_PAGES = 40

    /** UTC start of the current month, minus 7 days. Older rows stay on the server. */
    fun windowStartIso(now: Instant = Instant.now()): String {
        val date = now.atZone(ZoneOffset.UTC).toLocalDate()
        val start = date.withDayOfMonth(1).minusDays(7)
        return DateTimeFormatter.ISO_INSTANT.format(start.atStartOfDay(ZoneOffset.UTC).toInstant())
    }

    fun pagePath(basePath: String, page: Int): String {
        val separator = if (basePath.contains("?")) "&" else "?"
        val offset = page * PAGE_SIZE
        return "$basePath${separator}limit=$PAGE_SIZE&offset=$offset"
    }

    /**
     * Fetches pages until a short page. Throws if 40 full pages come back so the
     * caller can keep the previous local copy.
     */
    suspend fun fetchAll(basePath: String, fetch: suspend (String) -> Int): Int {
        var total = 0
        for (page in 0 until MAX_PAGES) {
            val count = fetch(pagePath(basePath, page))
            total += count
            if (count < PAGE_SIZE) return total
        }
        throw SyncOverflowException(
            "The server returned more rows than this sync can load. Nothing was replaced.",
        )
    }
}

class SyncOverflowException(message: String) : Exception(message)
