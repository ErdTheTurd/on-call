package com.eporthospine.mdshift.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.eporthospine.mdshift.data.AppConfig
import com.eporthospine.mdshift.data.AuthGate
import com.eporthospine.mdshift.data.AuthSnapshot
import com.eporthospine.mdshift.domain.UserRole

@Composable
fun AuthScreen(
    snapshot: AuthSnapshot,
    demoEnabled: Boolean,
    onSignIn: (email: String, password: String, role: UserRole) -> Unit,
    onSignUp: (email: String, password: String, confirm: String, role: UserRole) -> Unit,
    onVerifyCode: (String) -> Unit,
    onResend: () -> Unit,
    onVerifyMfa: (String) -> Unit,
    onConfirmEnroll: (String) -> Unit,
    onSkipEnroll: () -> Unit,
    onBack: () -> Unit,
    onGoogle: (UserRole) -> Unit,
    onApple: (UserRole) -> Unit,
    onExplore: (UserRole) -> Unit,
    onPrivacy: () -> Unit,
) {
    when (val gate = snapshot.gate) {
        is AuthGate.EmailCode -> CodeScreen(
            title = "Enter verification code",
            body = "We sent a 6-digit code to ${gate.email}. Enter it here — no link to click.",
            primary = "Verify and continue",
            busy = snapshot.busy,
            error = snapshot.error,
            info = snapshot.info,
            onSubmit = onVerifyCode,
            onResend = onResend,
            onBack = onBack,
        )
        is AuthGate.MfaChallenge -> CodeScreen(
            title = "Authenticator code",
            body = "Open Google Authenticator (or any TOTP app) and enter the 6-digit code for MD Shift.",
            primary = "Verify",
            busy = snapshot.busy,
            error = snapshot.error,
            info = snapshot.info,
            onSubmit = onVerifyMfa,
            onResend = null,
            onBack = onBack,
        )
        is AuthGate.MfaEnroll -> EnrollScreen(gate, snapshot, onConfirmEnroll, onSkipEnroll)
        else -> SignInScreen(snapshot, demoEnabled, onSignIn, onSignUp, onGoogle, onApple, onExplore, onPrivacy)
    }
}

@Composable
private fun SignInScreen(
    snapshot: AuthSnapshot,
    demoEnabled: Boolean,
    onSignIn: (String, String, UserRole) -> Unit,
    onSignUp: (String, String, String, UserRole) -> Unit,
    onGoogle: (UserRole) -> Unit,
    onApple: (UserRole) -> Unit,
    onExplore: (UserRole) -> Unit,
    onPrivacy: () -> Unit,
) {
    var signup by rememberSaveable { mutableStateOf(false) }
    var role by rememberSaveable { mutableStateOf(UserRole.Doctor.name) }
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var confirm by rememberSaveable { mutableStateOf("") }
    val selected = if (role == UserRole.Hospital.name) UserRole.Hospital else UserRole.Doctor
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Spacer(Modifier.height(24.dp))
        Text("MD Shift", style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold)
        Text("Smarter shift scheduling", color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FilterChip(selected = selected == UserRole.Doctor, onClick = { role = UserRole.Doctor.name }, label = { Text("Doctor") })
            FilterChip(selected = selected == UserRole.Hospital, onClick = { role = UserRole.Hospital.name }, label = { Text("Hospital") })
        }
        OutlinedButton(onClick = { onGoogle(selected) }, modifier = Modifier.fillMaxWidth()) { Text("Continue with Google") }
        OutlinedButton(onClick = { onApple(selected) }, modifier = Modifier.fillMaxWidth()) { Text("Continue with Apple") }
        Text("OR USE EMAIL", style = MaterialTheme.typography.labelMedium, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
        OutlinedTextField(email, { email = it }, label = { Text("Email") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
        OutlinedTextField(
            password, { password = it }, label = { Text("Password") }, modifier = Modifier.fillMaxWidth(),
            singleLine = true, visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        )
        if (signup) {
            OutlinedTextField(
                confirm, { confirm = it }, label = { Text("Confirm password") }, modifier = Modifier.fillMaxWidth(),
                singleLine = true, visualTransformation = PasswordVisualTransformation(),
            )
        }
        snapshot.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        PrimaryButton(
            text = if (signup) "Create account" else "Sign in",
            enabled = !snapshot.busy,
            onClick = {
                if (signup) onSignUp(email, password, confirm, selected) else onSignIn(email, password, selected)
            },
        )
        TextButton(onClick = { signup = !signup }, modifier = Modifier.fillMaxWidth()) {
            Text(if (signup) "Have an account? Sign in" else "New here? Create account")
        }
        if (demoEnabled) {
            TextButton(onClick = { onExplore(UserRole.Doctor) }, modifier = Modifier.fillMaxWidth()) { Text("Explore as a doctor") }
            TextButton(onClick = { onExplore(UserRole.Hospital) }, modifier = Modifier.fillMaxWidth()) { Text("Explore as a hospital") }
        }
        TextButton(onClick = onPrivacy, modifier = Modifier.fillMaxWidth()) {
            Text("By continuing you agree to our Privacy Policy and Terms of Service.")
        }
        Text(AppConfig.PRIVACY_URL, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
    }
}

@Composable
private fun CodeScreen(
    title: String,
    body: String,
    primary: String,
    busy: Boolean,
    error: String?,
    info: String?,
    onSubmit: (String) -> Unit,
    onResend: (() -> Unit)?,
    onBack: () -> Unit,
) {
    var code by rememberSaveable { mutableStateOf("") }
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Spacer(Modifier.height(24.dp))
        Text(title, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        Text(body)
        OutlinedTextField(
            code, { code = it.filter(Char::isDigit).take(6) },
            label = { Text("6-digit code") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
        )
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        info?.let { Text(it, color = Success) }
        PrimaryButton(primary, enabled = !busy) { onSubmit(code) }
        if (onResend != null) OutlinedButton(onClick = onResend, modifier = Modifier.fillMaxWidth()) { Text("Resend code") }
        TextButton(onClick = onBack) { Text("Back to sign in") }
    }
}

@Composable
private fun EnrollScreen(
    gate: AuthGate.MfaEnroll,
    snapshot: AuthSnapshot,
    onConfirm: (String) -> Unit,
    onSkip: () -> Unit,
) {
    var code by rememberSaveable { mutableStateOf("") }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Spacer(Modifier.height(24.dp))
        Text("Set up authenticator", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        Text("Add MD Shift in Google Authenticator using this secret, then enter the 6-digit code.")
        Text(gate.secret, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.titleMedium)
        OutlinedTextField(code, { code = it.filter(Char::isDigit).take(6) }, label = { Text("6-digit code") }, modifier = Modifier.fillMaxWidth())
        snapshot.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        PrimaryButton("Confirm and continue", enabled = !snapshot.busy) { onConfirm(code) }
        TextButton(onClick = onSkip) { Text("Skip for now") }
    }
}
