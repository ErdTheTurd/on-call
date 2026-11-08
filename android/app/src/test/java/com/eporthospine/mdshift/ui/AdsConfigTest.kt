package com.eporthospine.mdshift.ui

import com.eporthospine.mdshift.BuildConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class AdsConfigTest {
    @Test
    fun bannersStayOnGoogleTestIdsUntilThePublisherUnitsExist() {
        assertEquals("ca-app-pub-3940256099942544~3347511713", BuildConfig.ADMOB_APP_ID)
        assertEquals("ca-app-pub-3940256099942544/9214589741", BuildConfig.ADMOB_BANNER_AD_UNIT_ID)
        assertEquals("ca-app-pub-8874506793712009", BuildConfig.ADMOB_PUBLISHER_ID)
        assertFalse(BuildConfig.ADMOB_APP_ID.contains(BuildConfig.ADMOB_PUBLISHER_ID.removePrefix("ca-app-pub-")))
        assertFalse(BuildConfig.ADMOB_BANNER_AD_UNIT_ID.contains("8874506793712009"))
        assertEquals(60, AdsConfig.MAX_HEIGHT_DP)
    }
}
