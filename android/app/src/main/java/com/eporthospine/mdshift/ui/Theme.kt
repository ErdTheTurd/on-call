package com.eporthospine.mdshift.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import com.eporthospine.mdshift.domain.Appearance

val Accent = Color(0xFF2563EB)
val AccentDark = Color(0xFF4F8EF7)
val Purple = Color(0xFF7C3AED)
val Success = Color(0xFF059669)
val Danger = Color(0xFFDC2626)
val Warning = Color(0xFFD97706)
val Page = Color(0xFFF8FBFF)
val Ink = Color(0xFF0F172A)

private val LightColors = lightColorScheme(
    primary = Accent,
    onPrimary = Color.White,
    secondary = Purple,
    background = Page,
    surface = Color.White,
    error = Danger,
    onBackground = Ink,
    onSurface = Ink,
)

private val DarkColors = darkColorScheme(
    primary = AccentDark,
    secondary = Purple,
    background = Color(0xFF070B17),
    surface = Color(0xFF111827),
    error = Color(0xFFF87171),
)

@Composable
fun MdShiftTheme(appearance: String, content: @Composable () -> Unit) {
    val dark = when (appearance) {
        Appearance.Light.name -> false
        Appearance.Dark.name -> true
        else -> isSystemInDarkTheme()
    }
    MaterialTheme(colorScheme = if (dark) DarkColors else LightColors, content = content)
}
