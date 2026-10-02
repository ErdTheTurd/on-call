package com.eporthospine.mdshift.domain

data class NpiRecord(
    val npi: String,
    val firstName: String,
    val lastName: String,
    val credential: String,
    val taxonomy: String,
    val enumerationType: String,
    val organizationName: String?,
)

data class DoctorVerification(
    val record: NpiRecord?,
    val nameMatches: Boolean,
    val credentialMatches: Boolean,
    val emailDomainValid: Boolean,
    val status: VerificationStatus,
    val flags: List<String>,
    val checkedFirst: String = "",
    val checkedLast: String = "",
    val checkedCredential: String = "",
    val checkedNpi: String = "",
    val checkedLicense: String = "",
    val checkedState: String = "",
    val checkedEmail: String = "",
) {
    fun matches(
        first: String,
        last: String,
        credential: String,
        npi: String,
        license: String,
        state: String,
        email: String,
    ): Boolean =
        checkedFirst.trim().equals(first.trim(), ignoreCase = true) &&
            checkedLast.trim().equals(last.trim(), ignoreCase = true) &&
            checkedCredential.trim().equals(credential.trim(), ignoreCase = true) &&
            checkedNpi.filter(Char::isDigit) == npi.filter(Char::isDigit) &&
            checkedLicense.trim().equals(license.trim(), ignoreCase = true) &&
            checkedState.trim().equals(state.trim(), ignoreCase = true) &&
            checkedEmail.trim().equals(email.trim(), ignoreCase = true)
}

data class HospitalVerification(
    val record: NpiRecord?,
    val nameMatches: Boolean,
    val emailDomainValid: Boolean,
    val status: VerificationStatus,
    val flags: List<String>,
    val checkedName: String = "",
    val checkedNpi: String = "",
    val checkedEmail: String = "",
) {
    fun matches(name: String, npi: String, email: String): Boolean =
        checkedName.trim().equals(name.trim(), ignoreCase = true) &&
            checkedNpi.filter(Char::isDigit) == npi.filter(Char::isDigit) &&
            checkedEmail.trim().equals(email.trim(), ignoreCase = true)
}

object EmailDomainChecker {
    private val blocked = setOf(
        "gmail.com", "googlemail.com", "yahoo.com", "hotmail.com", "outlook.com",
        "icloud.com", "me.com", "mac.com", "aol.com",
        "protonmail.com", "proton.me", "tutanota.com",
        "live.com", "msn.com", "ymail.com",
        "privaterelay.appleid.com",
    )

    fun validate(email: String): String? {
        val parts = email.lowercase().trim().split("@")
        if (parts.size != 2 || parts[0].isEmpty() || !parts[1].contains(".")) {
            return "That doesn't look like a valid email address."
        }
        val domain = parts[1]
        if (blocked.contains(domain) || blocked.any { domain.endsWith(".$it") }) {
            return "Please use your institutional or hospital email, not a personal address."
        }
        return null
    }

    fun domainLikelyMatchesHospital(email: String, hospitalName: String): Boolean {
        val parts = email.lowercase().trim().split("@")
        if (parts.size != 2) return false
        val domainCore = parts[1].substringBeforeLast('.').replace(".", "")
        val words = hospitalName.lowercase().split(Regex("[^a-z0-9]+")).filter { it.length > 3 }
        if (words.isEmpty()) return true
        return words.any { domainCore.contains(it) }
    }
}

fun verifyDoctor(
    firstName: String,
    lastName: String,
    credential: String,
    email: String,
    emailProvidedByIdentityProvider: Boolean,
    record: NpiRecord?,
    lookupError: String?,
): DoctorVerification {
    val flags = mutableListOf<String>()
    val emailOk = if (emailProvidedByIdentityProvider && email.isNotBlank()) {
        true
    } else {
        val problem = EmailDomainChecker.validate(email)
        if (problem != null) flags += problem
        problem == null
    }
    var nameMatches = false
    var credentialMatches = false
    if (record != null) {
        nameMatches = record.firstName.trim().equals(firstName.trim(), ignoreCase = true) &&
            record.lastName.trim().equals(lastName.trim(), ignoreCase = true)
        if (!nameMatches) {
            flags += "Name '$firstName $lastName' doesn't match NPI registry ('${record.firstName} ${record.lastName}')."
        }
        val regCred = record.credential.replace(".", "").uppercase()
        val inCred = credential.replace(".", "").uppercase()
        credentialMatches = regCred.contains(inCred) || inCred.contains(regCred)
        if (!credentialMatches) {
            flags += "Credential '$credential' doesn't match registry ('${record.credential}')."
        }
    } else if (lookupError != null) {
        flags += "NPI lookup failed: $lookupError"
    }
    val passed = nameMatches && credentialMatches && emailOk && flags.isEmpty()
    val status = when {
        passed -> VerificationStatus.Pending
        record != null -> VerificationStatus.Flagged
        else -> VerificationStatus.Flagged
    }
    return DoctorVerification(
        record = record,
        nameMatches = nameMatches,
        credentialMatches = credentialMatches,
        emailDomainValid = emailOk,
        status = status,
        flags = flags,
        checkedFirst = firstName,
        checkedLast = lastName,
        checkedCredential = credential,
        checkedNpi = "",
        checkedEmail = email,
    )
}

fun verifyHospital(
    hospitalName: String,
    email: String,
    record: NpiRecord?,
    lookupError: String?,
): HospitalVerification {
    val flags = mutableListOf<String>()
    val emailProblem = EmailDomainChecker.validate(email)
    val emailOk = emailProblem == null
    if (emailProblem != null) flags += emailProblem
    if (emailOk && !EmailDomainChecker.domainLikelyMatchesHospital(email, hospitalName)) {
        flags += "Email domain doesn't clearly match '$hospitalName'. Confirm this is your hospital work email — our team will review."
    }
    var nameMatches = false
    if (record != null) {
        val regName = record.organizationName?.lowercase().orEmpty()
        val words = hospitalName.lowercase().split(Regex("\\s+")).filter { it.length > 3 }
        val hits = words.count { regName.contains(it) }
        nameMatches = words.isNotEmpty() && hits.toDouble() / words.size >= 0.6
        if (!nameMatches) {
            flags += "Hospital name '$hospitalName' doesn't clearly match registry ('${record.organizationName.orEmpty()}')."
        }
    } else if (lookupError != null) {
        flags += "NPI lookup failed: $lookupError"
    }
    val passed = nameMatches && emailOk && record != null
    return HospitalVerification(
        record = record,
        nameMatches = nameMatches,
        emailDomainValid = emailOk,
        status = if (passed) VerificationStatus.Pending else VerificationStatus.Flagged,
        flags = flags,
        checkedName = hospitalName,
        checkedEmail = email,
    )
}

/** Same debug shortcut the iOS app uses so local QA can finish onboarding offline. */
fun debugDoctorBypass(npi: String, licenseNumber: String, licenseState: String, email: String): Boolean =
    npi == "1234567890" &&
        licenseNumber.equals("a1234567", ignoreCase = true) &&
        licenseState.equals("tx", ignoreCase = true) &&
        email.lowercase().contains("@hospital.com")
