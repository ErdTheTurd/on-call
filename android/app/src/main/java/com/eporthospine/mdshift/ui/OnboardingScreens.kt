package com.eporthospine.mdshift.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.eporthospine.mdshift.data.AuthSnapshot
import com.eporthospine.mdshift.domain.Credential
import com.eporthospine.mdshift.domain.DoctorProfile
import com.eporthospine.mdshift.domain.DoctorVerification
import com.eporthospine.mdshift.domain.HospitalProfile
import com.eporthospine.mdshift.domain.HospitalVerification
import com.eporthospine.mdshift.domain.SPECIALTIES
import com.eporthospine.mdshift.domain.SchedulingPolicy

@Composable
fun DoctorOnboardingScreen(
    snapshot: AuthSnapshot,
    email: String,
    userId: String,
    onLookup: (first: String, last: String, credential: String, npi: String, license: String, state: String, email: String) -> Unit,
    verification: DoctorVerification?,
    onRequestEmail: (String) -> Unit,
    onVerifyEmail: (String, String) -> Unit,
    emailVerified: Boolean,
    onFinish: (DoctorProfile) -> Unit,
) {
    var step by rememberSaveable { mutableStateOf(0) }
    var first by rememberSaveable { mutableStateOf("") }
    var last by rememberSaveable { mutableStateOf("") }
    var credential by rememberSaveable { mutableStateOf(Credential.MD.wire) }
    var npi by rememberSaveable { mutableStateOf("") }
    var dea by rememberSaveable { mutableStateOf("") }
    var license by rememberSaveable { mutableStateOf("") }
    var stateName by rememberSaveable { mutableStateOf("") }
    var mail by rememberSaveable { mutableStateOf(email) }
    var specialties by rememberSaveable { mutableStateOf("") }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Doctor onboarding", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        Text("Step ${step + 1} of 4")
        when (step) {
            0 -> {
                OutlinedTextField(first, { first = it }, label = { Text("First name") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(last, { last = it }, label = { Text("Last name") }, modifier = Modifier.fillMaxWidth())
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Credential.entries.forEach { item ->
                        FilterChip(selected = credential == item.wire, onClick = { credential = item.wire }, label = { Text(item.wire) })
                    }
                }
                PrimaryButton("Continue", enabled = first.isNotBlank() && last.isNotBlank()) { step = 1 }
            }
            1 -> {
                OutlinedTextField(npi, { npi = it.filter(Char::isDigit).take(10) }, label = { Text("NPI") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(dea, { dea = it }, label = { Text("DEA (optional)") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(license, { license = it }, label = { Text("License number") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(stateName, { stateName = it }, label = { Text("License state") }, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(mail, { mail = it }, label = { Text("Work email") }, modifier = Modifier.fillMaxWidth())
                PrimaryButton("Verify NPI", enabled = !snapshot.busy) {
                    onLookup(first, last, credential, npi, license, stateName, mail)
                }
                verification?.let { result ->
                    Text(result.flags.joinToString("\n").ifBlank { "NPI registry matched. Status: ${result.status.wire}." })
                    result.record?.let { Text("Registry specialty: ${it.taxonomy}") }
                }
                snapshot.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                PrimaryButton("Continue", enabled = verification?.record != null) { step = if (email.isBlank()) 2 else 3 }
            }
            2 -> {
                var emailCode by rememberSaveable { mutableStateOf("") }
                Text("This account has no email yet. We will send a 6-digit code. There is no link to click.")
                OutlinedTextField(mail, { mail = it }, label = { Text("Email") }, modifier = Modifier.fillMaxWidth())
                PrimaryButton("Send code", enabled = !snapshot.busy) { onRequestEmail(mail) }
                OutlinedTextField(emailCode, { emailCode = it.filter(Char::isDigit).take(6) }, label = { Text("6-digit code") }, modifier = Modifier.fillMaxWidth())
                snapshot.info?.let { Text(it) }
                snapshot.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                PrimaryButton("Verify and continue", enabled = !snapshot.busy) {
                    onVerifyEmail(mail, emailCode)
                }
                if (emailVerified) {
                    PrimaryButton("Continue") { step = 3 }
                }
            }
            else -> {
                Text("Choose specialties")
                SPECIALTIES.chunked(2).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        row.forEach { name ->
                            val selected = specialties.split(",").contains(name)
                            FilterChip(
                                selected = selected,
                                onClick = {
                                    val current = specialties.split(",").filter { it.isNotBlank() }.toMutableSet()
                                    if (!current.add(name)) current.remove(name)
                                    specialties = current.joinToString(",")
                                },
                                label = { Text(name) },
                            )
                        }
                    }
                }
                verification?.record?.taxonomy?.takeIf { it.isNotBlank() }?.let { Text("NPI taxonomy: $it") }
                snapshot.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                PrimaryButton("Finish", enabled = !snapshot.busy && specialties.isNotBlank()) {
                    val result = verification
                    onFinish(
                        DoctorProfile(
                            id = userId,
                            userId = userId,
                            firstName = first.trim(),
                            lastName = last.trim(),
                            credential = credential,
                            npi = npi,
                            deaNumber = dea,
                            licenseNumber = license,
                            licenseState = stateName,
                            specialties = specialties.split(",").filter { it.isNotBlank() },
                            email = mail.trim(),
                            verificationStatus = result?.status?.wire ?: "pending",
                            verificationFlags = result?.flags ?: emptyList(),
                            npiRegistryName = result?.record?.let { "${it.firstName} ${it.lastName}" },
                            npiTaxonomy = result?.record?.taxonomy,
                        ),
                    )
                }
            }
        }
    }
}

@Composable
fun HospitalOnboardingScreen(
    snapshot: AuthSnapshot,
    email: String,
    userId: String,
    hospitalId: String,
    onLookup: (name: String, npi: String, email: String) -> Unit,
    verification: HospitalVerification?,
    onSendCode: (email: String, name: String) -> Unit,
    onVerifyCode: (email: String, code: String) -> Unit,
    codeVerified: Boolean,
    onFinish: (HospitalProfile) -> Unit,
) {
    var step by rememberSaveable { mutableStateOf(0) }
    var name by rememberSaveable { mutableStateOf("") }
    var npi by rememberSaveable { mutableStateOf("") }
    var mail by rememberSaveable { mutableStateOf(email) }
    var code by rememberSaveable { mutableStateOf("") }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("Hospital onboarding", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
        if (step == 0) {
            OutlinedTextField(name, { name = it }, label = { Text("Facility name") }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(npi, { npi = it.filter(Char::isDigit).take(10) }, label = { Text("Organization NPI") }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(mail, { mail = it }, label = { Text("Work email") }, modifier = Modifier.fillMaxWidth())
            PrimaryButton("Verify facility", enabled = !snapshot.busy) { onLookup(name, npi, mail) }
            verification?.let { result ->
                Text(result.flags.joinToString("\n").ifBlank { "Facility checks passed. Status: ${result.status.wire}." })
            }
            snapshot.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            PrimaryButton("Continue", enabled = verification?.record != null && verification.emailDomainValid) {
                onSendCode(mail, name)
                step = 1
            }
        } else {
            Text("Enter the 6-digit code sent to $mail. This confirms your hospital work email.")
            OutlinedTextField(code, { code = it.filter(Char::isDigit).take(6) }, label = { Text("Work email code") }, modifier = Modifier.fillMaxWidth())
            snapshot.info?.let { Text(it) }
            snapshot.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            PrimaryButton("Verify code", enabled = !snapshot.busy) { onVerifyCode(mail, code) }
            PrimaryButton("Finish", enabled = codeVerified && !snapshot.busy) {
                val result = verification
                onFinish(
                    HospitalProfile(
                        id = hospitalId,
                        userId = userId,
                        name = name.trim(),
                        npi = npi,
                        email = mail.trim(),
                        verificationStatus = result?.status?.wire ?: "pending",
                        verificationFlags = result?.flags ?: emptyList(),
                        npiRegistryName = result?.record?.organizationName,
                        policy = SchedulingPolicy(),
                    ),
                )
            }
        }
    }
}
