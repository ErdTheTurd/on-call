package com.eporthospine.mdshift.ui

import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import com.eporthospine.mdshift.data.AuthGate
import com.eporthospine.mdshift.data.AuthSnapshot
import com.eporthospine.mdshift.domain.UserRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], qualifiers = "w480dp-h2000dp", application = android.app.Application::class)
class AuthScreenTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun releaseSignInHidesExploreAndKeepsBothRoles() {
        var role = UserRole.Doctor
        compose.setContent {
            MdShiftTheme(appearance = "Light") {
                AuthScreen(
                    snapshot = AuthSnapshot(),
                    demoEnabled = false,
                    onSignIn = { _, _, selected -> role = selected },
                    onSignUp = { _, _, _, _ -> },
                    onVerifyCode = {},
                    onResend = {},
                    onVerifyMfa = {},
                    onConfirmEnroll = {},
                    onSkipEnroll = {},
                    onBack = {},
                    onGoogle = {},
                    onApple = {},
                    onExplore = {},
                    onPrivacy = {},
                )
            }
        }
        compose.onNodeWithText("Continue with Google").fetchSemanticsNode()
        compose.onNodeWithText("Continue with Apple").fetchSemanticsNode()
        assertTrue(compose.onAllNodesWithText("Explore as a doctor").fetchSemanticsNodes().isEmpty())
        assertTrue(compose.onAllNodesWithText("Explore as a hospital").fetchSemanticsNodes().isEmpty())
        compose.onNodeWithText("Privacy Policy", substring = true).fetchSemanticsNode()
        compose.onNodeWithText("Hospital").performClick()
        compose.onNodeWithText("Sign in").performClick()
        assertEquals(UserRole.Hospital, role)
    }

    @Test
    fun debugExploreIsVisible() {
        var explored: UserRole? = null
        compose.setContent {
            MdShiftTheme(appearance = "Light") {
                AuthScreen(
                    snapshot = AuthSnapshot(AuthGate.LoggedOut),
                    demoEnabled = true,
                    onSignIn = { _, _, _ -> },
                    onSignUp = { _, _, _, _ -> },
                    onVerifyCode = {},
                    onResend = {},
                    onVerifyMfa = {},
                    onConfirmEnroll = {},
                    onSkipEnroll = {},
                    onBack = {},
                    onGoogle = {},
                    onApple = {},
                    onExplore = { explored = it },
                    onPrivacy = {},
                )
            }
        }
        compose.onNodeWithText("Explore as a doctor").performClick()
        assertEquals(UserRole.Doctor, explored)
    }
}
