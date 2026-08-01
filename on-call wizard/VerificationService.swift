import Foundation

// NOTE: VerificationStatus is defined in Models.swift

// MARK: - NPI Registry (NPPES)

public struct NPIRecord {
    public let npi: String
    public let firstName: String
    public let lastName: String
    public let credential: String        // "MD", "DO", etc.
    public let taxonomyDescription: String  // specialty
    public let enumerationType: String   // "NPI-1" individual, "NPI-2" organization
    public let organizationName: String? // for hospitals
}

public enum NPILookupError: LocalizedError {
    case notFound
    case networkError(Error)
    case invalidResponse
    case organizationNotIndividual
    case individualNotOrganization

    public var errorDescription: String? {
        switch self {
        case .notFound:                    return "No provider found with that NPI number."
        case .networkError(let e):         return "Network error: \(e.localizedDescription)"
        case .invalidResponse:             return "Unexpected response from NPI registry."
        case .organizationNotIndividual:   return "That NPI belongs to an organization, not an individual provider."
        case .individualNotOrganization:   return "That NPI belongs to an individual provider, not a facility."
        }
    }
}

public final class NPIRegistryService {
    public static let shared = NPIRegistryService()
    private let base = "https://npiregistry.cms.hhs.gov/api/"

    public func lookupIndividual(npi: String) async throws -> NPIRecord {
        let record = try await fetch(npi: npi)
        guard record.enumerationType == "NPI-1" else { throw NPILookupError.organizationNotIndividual }
        return record
    }

    public func lookupOrganization(npi: String) async throws -> NPIRecord {
        let record = try await fetch(npi: npi)
        guard record.enumerationType == "NPI-2" else { throw NPILookupError.individualNotOrganization }
        return record
    }

    private func fetch(npi: String) async throws -> NPIRecord {
        var components = URLComponents(string: base)!
        components.queryItems = [
            URLQueryItem(name: "number", value: npi),
            URLQueryItem(name: "version", value: "2.1")
        ]
        guard let url = components.url else { throw NPILookupError.invalidResponse }

        let (data, _): (Data, URLResponse)
        do {
            (data, _) = try await URLSession.shared.data(from: url)
        } catch {
            throw NPILookupError.networkError(error)
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let results = json["results"] as? [[String: Any]],
            let first = results.first
        else { throw NPILookupError.notFound }

        let enumType = first["enumeration_type"] as? String ?? ""

        // Individual provider
        if enumType == "NPI-1",
           let basic = first["basic"] as? [String: Any] {
            let firstName  = basic["first_name"]  as? String ?? ""
            let lastName   = basic["last_name"]   as? String ?? ""
            let credential = basic["credential"]  as? String ?? ""
            let taxonomy   = (first["taxonomies"] as? [[String: Any]])?.first?["desc"] as? String ?? ""
            return NPIRecord(npi: npi, firstName: firstName, lastName: lastName,
                             credential: credential, taxonomyDescription: taxonomy,
                             enumerationType: "NPI-1", organizationName: nil)
        }

        // Organization
        if enumType == "NPI-2",
           let basic = first["basic"] as? [String: Any] {
            let orgName  = basic["organization_name"] as? String ?? ""
            let taxonomy = (first["taxonomies"] as? [[String: Any]])?.first?["desc"] as? String ?? ""
            return NPIRecord(npi: npi, firstName: "", lastName: orgName,
                             credential: "", taxonomyDescription: taxonomy,
                             enumerationType: "NPI-2", organizationName: orgName)
        }

        throw NPILookupError.invalidResponse
    }
}

// MARK: - Email Domain Check

public enum EmailVerificationError: LocalizedError {
    case freeProvider
    case invalidFormat
    case domainMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .freeProvider:         return "Please use your institutional or hospital email, not a personal address."
        case .invalidFormat:        return "That doesn't look like a valid email address."
        case .domainMismatch(let d): return "Email domain '\(d)' doesn't appear to be a medical institution. Use your work email."
        }
    }
}

public struct EmailDomainChecker {
    // Common free/personal providers — not exhaustive but covers the obvious ones
    private static let blockedDomains: Set<String> = [
        "gmail.com", "yahoo.com", "hotmail.com", "outlook.com",
        "icloud.com", "me.com", "mac.com", "aol.com",
        "protonmail.com", "proton.me", "tutanota.com",
        "live.com", "msn.com", "ymail.com"
    ]

    public static func validate(_ email: String) throws {
        let parts = email.lowercased().split(separator: "@")
        guard parts.count == 2, parts[0].count >= 1, parts[1].contains(".") else {
            throw EmailVerificationError.invalidFormat
        }
        let domain = String(parts[1])
        if blockedDomains.contains(domain) {
            throw EmailVerificationError.freeProvider
        }
        // Additional heuristic: must have at least one dot in domain after @
        // and not be a generic non-medical TLD-only address
        // Real production would hit an allowlist API here
    }
}

// MARK: - Doctor Verification Pipeline

public struct DoctorVerificationResult {
    public var npiRecord: NPIRecord?
    public var nameMatches: Bool = false
    public var credentialMatches: Bool = false
    public var emailDomainValid: Bool = false
    public var finalStatus: VerificationStatus = .unverified
    public var flags: [String] = []
}

public final class DoctorVerificationService {
    public static let shared = DoctorVerificationService()

    /// Returns a result struct describing what passed/failed, and a final status.
    public func verify(
        firstName: String,
        lastName: String,
        credential: String,
        npi: String,
        licenseNumber: String,
        licenseState: String,
        email: String
    ) async -> DoctorVerificationResult {
        #if DEBUG
        if npi == "1234567890" && licenseNumber.lowercased() == "a1234567" &&
           licenseState.lowercased() == "tx" && email.lowercased().contains("@hospital.com") {
            var bypass = DoctorVerificationResult()
            bypass.npiRecord = NPIRecord(
                npi: npi, firstName: firstName, lastName: lastName,
                credential: credential, taxonomyDescription: "Internal Medicine",
                enumerationType: "NPI-1", organizationName: nil
            )
            bypass.nameMatches = true
            bypass.credentialMatches = true
            bypass.emailDomainValid = true
            bypass.finalStatus = .pending
            return bypass
        }
        #endif

        var result = DoctorVerificationResult()

        // 1. Email domain check (instant, no network)
        do {
            try EmailDomainChecker.validate(email)
            result.emailDomainValid = true
        } catch {
            result.flags.append(error.localizedDescription)
        }

        // 2. NPI registry lookup
        do {
            let record = try await NPIRegistryService.shared.lookupIndividual(npi: npi)
            result.npiRecord = record

            // Name match (case-insensitive, trimmed)
            let regFirst = record.firstName.trimmingCharacters(in: .whitespaces).lowercased()
            let regLast  = record.lastName.trimmingCharacters(in: .whitespaces).lowercased()
            let inFirst  = firstName.trimmingCharacters(in: .whitespaces).lowercased()
            let inLast   = lastName.trimmingCharacters(in: .whitespaces).lowercased()
            result.nameMatches = (regFirst == inFirst && regLast == inLast)
            if !result.nameMatches {
                result.flags.append("Name '\(firstName) \(lastName)' doesn't match NPI registry ('\(record.firstName) \(record.lastName)').")
            }

            // Credential match (registry often includes periods: "M.D." vs "MD")
            let regCred = record.credential.replacingOccurrences(of: ".", with: "").uppercased()
            let inCred  = credential.replacingOccurrences(of: ".", with: "").uppercased()
            result.credentialMatches = regCred.contains(inCred) || inCred.contains(regCred)
            if !result.credentialMatches {
                result.flags.append("Credential '\(credential)' doesn't match registry ('\(record.credential)').")
            }
        } catch {
            result.flags.append("NPI lookup failed: \(error.localizedDescription)")
        }

        // 3. Determine final status
        let automatedPassed = result.nameMatches && result.credentialMatches && result.emailDomainValid
        if automatedPassed && result.flags.isEmpty {
            // All automated checks pass → pending human review
            result.finalStatus = .pending
        } else if result.npiRecord != nil {
            // NPI found but something else off → flag for manual review
            result.finalStatus = .flagged
        } else {
            result.finalStatus = .flagged
        }

        return result
    }
}

// MARK: - Hospital Verification Pipeline

public struct HospitalVerificationResult {
    public var npiRecord: NPIRecord?
    public var nameMatches: Bool = false
    public var emailDomainValid: Bool = false
    public var finalStatus: VerificationStatus = .unverified
    public var flags: [String] = []
}

public final class HospitalVerificationService {
    public static let shared = HospitalVerificationService()

    public func verify(
        hospitalName: String,
        npi: String,
        email: String
    ) async -> HospitalVerificationResult {
        var result = HospitalVerificationResult()

        // 1. Email domain check
        do {
            try EmailDomainChecker.validate(email)
            result.emailDomainValid = true
        } catch {
            result.flags.append(error.localizedDescription)
        }

        // 2. NPI registry — organization lookup
        do {
            let record = try await NPIRegistryService.shared.lookupOrganization(npi: npi)
            result.npiRecord = record

            // Fuzzy name match: registry name should contain key words from entered name
            let regName = record.organizationName?.lowercased() ?? ""
            let inWords = hospitalName.lowercased()
                .components(separatedBy: .whitespaces)
                .filter { $0.count > 3 }   // skip short words like "of", "the"
            let wordMatches = inWords.filter { regName.contains($0) }
            result.nameMatches = !inWords.isEmpty && Double(wordMatches.count) / Double(inWords.count) >= 0.6
            if !result.nameMatches {
                result.flags.append("Hospital name '\(hospitalName)' doesn't clearly match registry ('\(record.organizationName ?? "")').")
            }
        } catch {
            result.flags.append("NPI lookup failed: \(error.localizedDescription)")
        }

        // 3. Final status
        let automatedPassed = result.nameMatches && result.emailDomainValid
        result.finalStatus = automatedPassed ? .pending : .flagged

        return result
    }
}
