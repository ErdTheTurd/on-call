/** NPI registry + email domain checks (ported from iOS VerificationService). */

const NPI_API = "https://npiregistry.cms.hhs.gov/api/";

const BLOCKED_EMAIL_DOMAINS = new Set([
  "gmail.com", "yahoo.com", "hotmail.com", "outlook.com",
  "icloud.com", "me.com", "mac.com", "aol.com",
  "protonmail.com", "proton.me", "tutanota.com",
  "live.com", "msn.com", "ymail.com"
]);

export async function lookupNPI(npi, expectType = "NPI-1") {
  const number = String(npi || "").replace(/\D/g, "");
  if (number.length !== 10) throw new Error("NPI must be 10 digits.");

  const url = `${NPI_API}?number=${encodeURIComponent(number)}&version=2.1`;
  let json;
  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`NPI registry returned ${res.status}`);
    json = await res.json();
  } catch (err) {
    // CMS NPPES often blocks browser CORS — fall back to offline validation.
    if (err?.message?.includes("Failed to fetch") || err?.name === "TypeError") {
      return {
        npi: number,
        firstName: "",
        lastName: "",
        credential: "",
        taxonomyDescription: "",
        enumerationType: expectType,
        organizationName: expectType === "NPI-2" ? "" : null,
        offline: true
      };
    }
    throw err;
  }

  const first = json?.results?.[0];
  if (!first) throw new Error("No provider found with that NPI number.");

  const enumType = first.enumeration_type || "";
  const basic = first.basic || {};
  const taxonomy = first.taxonomies?.[0]?.desc || "";

  if (enumType === "NPI-1") {
    if (expectType === "NPI-2") {
      throw new Error("That NPI belongs to an individual provider, not a facility.");
    }
    return {
      npi: number,
      firstName: basic.first_name || "",
      lastName: basic.last_name || "",
      credential: basic.credential || "",
      taxonomyDescription: taxonomy,
      enumerationType: "NPI-1",
      organizationName: null,
      offline: false
    };
  }

  if (enumType === "NPI-2") {
    if (expectType === "NPI-1") {
      throw new Error("That NPI belongs to an organization, not an individual provider.");
    }
    return {
      npi: number,
      firstName: "",
      lastName: basic.organization_name || "",
      credential: "",
      taxonomyDescription: taxonomy,
      enumerationType: "NPI-2",
      organizationName: basic.organization_name || "",
      offline: false
    };
  }

  throw new Error("Unexpected response from NPI registry.");
}

export function validateInstitutionalEmail(email) {
  const parts = String(email || "").toLowerCase().split("@");
  if (parts.length !== 2 || !parts[0] || !parts[1].includes(".")) {
    return { ok: false, error: "That doesn't look like a valid email address." };
  }
  if (BLOCKED_EMAIL_DOMAINS.has(parts[1])) {
    return { ok: false, error: "Please use your institutional or hospital email, not a personal address." };
  }
  return { ok: true, domain: parts[1] };
}

export function verifyDoctorCredentials({ firstName, lastName, credential, npiRecord, email }) {
  const flags = [];
  let nameMatches = true;
  let credentialMatches = true;
  const emailCheck = validateInstitutionalEmail(email);
  const emailDomainValid = emailCheck.ok;

  if (!emailDomainValid) flags.push(emailCheck.error);

  if (npiRecord && !npiRecord.offline) {
    const fn = (npiRecord.firstName || "").toLowerCase();
    const ln = (npiRecord.lastName || "").toLowerCase();
    if (fn && firstName && fn !== firstName.toLowerCase()) {
      nameMatches = false;
      flags.push("First name does not match NPI registry.");
    }
    if (ln && lastName && ln !== lastName.toLowerCase()) {
      nameMatches = false;
      flags.push("Last name does not match NPI registry.");
    }
    const cred = (npiRecord.credential || "").toUpperCase();
    if (cred && credential && !cred.includes(String(credential).toUpperCase())) {
      credentialMatches = false;
      flags.push("Credential does not match NPI registry.");
    }
  } else if (npiRecord?.offline) {
    flags.push("NPI registry unreachable from browser — credentials queued for manual review.");
  }

  let finalStatus = "pending";
  if (!emailDomainValid || (!nameMatches && npiRecord && !npiRecord.offline)) {
    finalStatus = "flagged";
  } else if (npiRecord && !npiRecord.offline && nameMatches && credentialMatches && emailDomainValid) {
    finalStatus = "pending";
  }

  return {
    npiRecord,
    nameMatches,
    credentialMatches,
    emailDomainValid,
    finalStatus,
    flags
  };
}
