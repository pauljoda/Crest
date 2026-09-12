import Foundation

enum BrowserSiteDataPolicy {
    static func matchesDataRecord(displayName: String, host: String) -> Bool {
        let record = normalizedHost(displayName)
        let host = normalizedHost(host)
        guard !record.isEmpty, !host.isEmpty else { return false }
        return record == host
            || host.hasSuffix(".\(record)")
            || record.hasSuffix(".\(host)")
    }

    /// Site-data deletion intentionally includes parent domains. This is not
    /// request eligibility: it does not model host-only, Secure, path or SameSite.
    static func includesCookieDomainForRemoval(_ domain: String, host: String) -> Bool {
        let domain = normalizedHost(domain)
        let host = normalizedHost(host)
        guard !domain.isEmpty, !host.isEmpty else { return false }
        return domain == host || host.hasSuffix(".\(domain)")
    }

    private static func normalizedHost(_ value: String) -> String {
        value.lowercased().trimmingCharacters(
            in: CharacterSet(charactersIn: ".")
        )
    }
}
