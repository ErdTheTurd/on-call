package com.eporthospine.mdshift.domain

import java.math.BigDecimal
import java.math.RoundingMode
import kotlin.math.max

object EscalationCurve {
    private val hourBreakpoints = listOf(
        72.0 to 1.00, 48.0 to 1.15, 24.0 to 1.35, 12.0 to 1.60, 6.0 to 1.85, 2.0 to 2.20, 0.0 to 2.20,
    )
    private val dayBreakpoints = listOf(
        30.0 to 1.00, 14.0 to 1.10, 7.0 to 1.20, 3.0 to 1.35, 1.0 to 1.60, 0.0 to 2.00,
    )

    fun multiplierForHours(hours: Double): Double = interpolate(hours, hourBreakpoints)
    fun multiplierForDays(days: Double): Double = interpolate(days, dayBreakpoints)

    fun currentRate(shift: Shift, nowEpochMillis: Long): Double {
        val hours = hoursUntil(shift.startEpochMillis, nowEpochMillis)
        val floor = shift.rateFloor
        val flat = shift.flatRate
        if (flat != null) return max(floor, flat)
        val multiplier = if (shift.perDay) multiplierForDays(hours / 24.0) else multiplierForHours(hours)
        return floor * multiplier
    }

    fun urgencyLabel(hoursUntilShift: Double, perDay: Boolean): String {
        if (perDay) {
            val days = hoursUntilShift / 24.0
            return when {
                days < 0 -> "Past"
                days < 1 -> "Critical"
                days < 3 -> "High"
                days < 7 -> "Moderate"
                else -> "Low"
            }
        }
        return when {
            hoursUntilShift < 0 -> "Past"
            hoursUntilShift < 12 -> "Critical"
            hoursUntilShift < 24 -> "High"
            hoursUntilShift < 48 -> "Moderate"
            else -> "Low"
        }
    }

    private fun interpolate(value: Double, breakpoints: List<Pair<Double, Double>>): Double {
        if (value <= 0) return breakpoints.last().second
        for (i in 0 until breakpoints.size - 1) {
            val (h1, m1) = breakpoints[i]
            val (h2, m2) = breakpoints[i + 1]
            if (value <= h1 && value >= h2) {
                val t = (h1 - value) / (h1 - h2)
                return m1 + (m2 - m1) * t
            }
        }
        return breakpoints.first().second
    }
}

enum class SchedulingAction { Cancel, Trade }

data class PolicyPreview(
    val allowed: Boolean,
    val penaltyAmount: Double,
    val penaltyPercent: Double,
    val hoursRemaining: Double,
    val windowHours: Int,
    val action: SchedulingAction,
)

object PenaltyCalculator {
    fun preview(
        action: SchedulingAction,
        policy: SchedulingPolicy,
        shiftStartEpochMillis: Long,
        nowEpochMillis: Long,
        baseAmountOverride: Double? = null,
    ): PolicyPreview {
        val hours = hoursUntil(shiftStartEpochMillis, nowEpochMillis)
        val window = if (action == SchedulingAction.Cancel) policy.cancelWindowHours else policy.tradeWindowHours
        val (percent, amount) = when (action) {
            SchedulingAction.Cancel -> {
                val pct = percentFor(hours, policy.cancellationPenaltyScale)
                val base = baseAmountOverride ?: policy.basePenaltyAmount
                pct to round2(base * pct)
            }
            SchedulingAction.Trade -> tradePenalty(hours, policy)
        }
        return PolicyPreview(
            allowed = hours > window.toDouble(),
            penaltyAmount = amount,
            penaltyPercent = percent,
            hoursRemaining = hours,
            windowHours = window,
            action = action,
        )
    }

    private fun tradePenalty(hoursRemaining: Double, policy: SchedulingPolicy): Pair<Double, Double> {
        if (!policy.tradePenaltiesEnabled) return 0.0 to 0.0
        if (hoursRemaining <= policy.tradePenaltyHoursBeforeStart.toDouble()) {
            return 1.0 to round2(policy.tradePenaltyAmount)
        }
        return 0.0 to 0.0
    }

    private fun percentFor(hoursRemaining: Double, scale: List<PenaltyBracket>): Double {
        for (bracket in scale.sortedBy { it.hoursBeforeStart }) {
            if (hoursRemaining <= bracket.hoursBeforeStart.toDouble()) {
                return bracket.penaltyPercent.coerceIn(1.0, 5.0)
            }
        }
        return 1.0
    }
}

fun hoursUntil(startEpochMillis: Long, nowEpochMillis: Long): Double =
    max(0.0, (startEpochMillis - nowEpochMillis) / 3_600_000.0)

fun round2(value: Double): Double =
    BigDecimal.valueOf(value).setScale(2, RoundingMode.HALF_UP).toDouble()

/** Savings versus the escalation ceiling (2.0 per day, 2.2 per hour). */
fun earlyFillSavings(shift: Shift, nowEpochMillis: Long): Double {
    val ceiling = if (shift.perDay) 2.0 else 2.2
    val current = EscalationCurve.currentRate(shift, nowEpochMillis)
    val units = if (shift.perDay) 1.0 else shift.durationHours.toDouble()
    return max(0.0, (shift.rateFloor * ceiling - current) * units)
}
