package com.eporthospine.mdshift.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class PricingAndPagingTest {
    @Test
    fun dayEscalationInterpolatesBetweenBreakpoints() {
        val seven = EscalationCurve.multiplierForDays(7.0)
        assertEquals(1.20, seven, 0.001)
        val halfway = EscalationCurve.multiplierForDays(10.5)
        assertEquals(1.15, halfway, 0.001)
        assertEquals(2.0, EscalationCurve.multiplierForDays(0.0), 0.001)
    }

    @Test
    fun hourEscalationAndFlatRate() {
        assertEquals(1.35, EscalationCurve.multiplierForHours(24.0), 0.001)
        val shift = Shift(
            id = "s",
            hospitalId = "h",
            hospitalName = "H",
            specialty = "Cardiology",
            startEpochMillis = 0L,
            rateFloor = 1000.0,
            perDay = false,
            flatRate = 1500.0,
        )
        assertEquals(1500.0, EscalationCurve.currentRate(shift, 0L), 0.001)
    }

    @Test
    fun cancelPenaltyUsesScaleAndWindow() {
        val policy = SchedulingPolicy(basePenaltyAmount = 100.0, cancelWindowHours = 6)
        val soon = PenaltyCalculator.preview(SchedulingAction.Cancel, policy, shiftStartEpochMillis = 5 * 3_600_000L, nowEpochMillis = 0L)
        assertFalse(soon.allowed)
        val later = PenaltyCalculator.preview(
            SchedulingAction.Cancel,
            policy,
            shiftStartEpochMillis = 10 * 3_600_000L,
            nowEpochMillis = 0L,
            baseAmountOverride = 100.0,
        )
        assertTrue(later.allowed)
        assertEquals(200.0, later.penaltyAmount, 0.001)
        val far = PenaltyCalculator.preview(SchedulingAction.Cancel, policy, shiftStartEpochMillis = 100 * 3_600_000L, nowEpochMillis = 0L, baseAmountOverride = 100.0)
        assertEquals(100.0, far.penaltyAmount, 0.001)
    }

    @Test
    fun tradePenaltyIsFlatInsideLeadTime() {
        val policy = SchedulingPolicy()
        val inside = PenaltyCalculator.preview(SchedulingAction.Trade, policy, 48 * 3_600_000L, 0L)
        assertEquals(250.0, inside.penaltyAmount, 0.001)
        assertTrue(inside.allowed)
        val outside = PenaltyCalculator.preview(SchedulingAction.Trade, policy, 80 * 3_600_000L, 0L)
        assertEquals(0.0, outside.penaltyAmount, 0.001)
        val blocked = PenaltyCalculator.preview(SchedulingAction.Trade, policy, 2 * 3_600_000L, 0L)
        assertFalse(blocked.allowed)
    }

    @Test
    fun windowStartsSevenDaysBeforeUtcMonth() {
        val now = Instant.parse("2026-10-02T15:00:00Z")
        assertEquals("2026-09-24T00:00:00Z", PostgRestPages.windowStartIso(now))
        val march = Instant.parse("2026-03-01T00:30:00Z")
        assertEquals("2026-02-22T00:00:00Z", PostgRestPages.windowStartIso(march))
    }

    @Test
    fun pagesAreOrderedAndCapped() {
        assertEquals(
            "rest/v1/shifts?select=*&date=gte.2026-09-24T00:00:00Z&limit=1000&offset=0",
            PostgRestPages.pagePath("rest/v1/shifts?select=*&date=gte.2026-09-24T00:00:00Z", 0),
        )
        assertTrue(PostgRestPages.pagePath("rest/v1/shifts?select=*", 2).endsWith("limit=1000&offset=2000"))
    }

    @Test
    fun overflowKeepsCallerFromReplacingRows() {
        var calls = 0
        try {
            kotlinx.coroutines.test.runTest {
                PostgRestPages.fetchAll("rest/v1/shifts?select=*") {
                    calls += 1
                    PostgRestPages.PAGE_SIZE
                }
            }
            throw AssertionError("expected overflow")
        } catch (error: SyncOverflowException) {
            assertEquals(PostgRestPages.MAX_PAGES, calls)
            assertTrue(error.message!!.contains("Nothing was replaced"))
        }
    }

    @Test
    fun shortPageStops() {
        kotlinx.coroutines.test.runTest {
            val total = PostgRestPages.fetchAll("rest/v1/shifts?select=*") { path ->
                if (path.contains("offset=0")) PostgRestPages.PAGE_SIZE else 3
            }
            assertEquals(PostgRestPages.PAGE_SIZE + 3, total)
        }
    }

    @Test
    fun demoStaysOffReleaseAndOffRealSessions() {
        assertFalse(demoModeEnabled(debug = false, internalTesting = false))
        assertTrue(demoModeEnabled(debug = true, internalTesting = false))
        assertTrue(demoModeEnabled(debug = false, internalTesting = true))
        assertFalse(usesLocalSampleData(demoEnabled = true, accessToken = "jwt"))
        assertTrue(usesLocalSampleData(demoEnabled = true, accessToken = null))
        assertFalse(usesLocalSampleData(demoEnabled = false, accessToken = null))
    }

    @Test
    fun onboardingRequiresNameAndNpi() {
        val doctor = DoctorProfile("id", "id", "A", "B", "MD", npi = "1234567890")
        assertTrue(doctor.isOnboardingComplete)
        assertFalse(doctor.copy(npi = "123").isOnboardingComplete)
        val hospital = HospitalProfile("h", "u", "Average", "1098765432", "a@b.org")
        assertTrue(hospital.isOnboardingComplete)
        assertFalse(hospital.copy(email = "not-an-email").isOnboardingComplete)
    }
}
