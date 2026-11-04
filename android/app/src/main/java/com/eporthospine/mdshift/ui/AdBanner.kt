package com.eporthospine.mdshift.ui

import android.os.Build
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.viewinterop.AndroidView
import com.eporthospine.mdshift.BuildConfig
import com.google.android.gms.ads.AdListener
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView

/**
 * Google's public test IDs. They do not bill publisher [BuildConfig.ADMOB_PUBLISHER_ID].
 * TODO: Replace [BuildConfig.ADMOB_APP_ID] and [BuildConfig.ADMOB_BANNER_AD_UNIT_ID]
 * with the AdMob app and banner unit created under that publisher.
 */
object AdsConfig {
    const val MAX_HEIGHT_DP = 60

    fun disabledInThisProcess(): Boolean =
        Build.FINGERPRINT.contains("robolectric", ignoreCase = true) ||
            Build.HARDWARE.contains("robolectric", ignoreCase = true)
}

/** Short inline adaptive banner at the bottom of a main list. It does not float over buttons. */
@Composable
fun AdBanner(modifier: Modifier = Modifier) {
    if (AdsConfig.disabledInThisProcess()) return
    var filled by remember { mutableStateOf(false) }
    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .semantics { contentDescription = "Advertisement" },
    ) {
        val widthDp = maxWidth.value.toInt().coerceAtLeast(1)
        Column(Modifier.fillMaxWidth()) {
            if (filled) {
                Text(
                    "ADVERTISEMENT",
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.45f),
                )
            }
            AndroidView(
                modifier = Modifier.fillMaxWidth(),
                factory = { context ->
                    AdView(context).apply {
                        adUnitId = BuildConfig.ADMOB_BANNER_AD_UNIT_ID
                        setAdSize(AdSize.getInlineAdaptiveBannerAdSize(widthDp, AdsConfig.MAX_HEIGHT_DP))
                        adListener = object : AdListener() {
                            override fun onAdLoaded() {
                                filled = true
                            }

                            override fun onAdFailedToLoad(error: com.google.android.gms.ads.LoadAdError) {
                                filled = false
                            }
                        }
                        loadAd(AdRequest.Builder().build())
                    }
                },
                onRelease = { it.destroy() },
            )
        }
    }
}
