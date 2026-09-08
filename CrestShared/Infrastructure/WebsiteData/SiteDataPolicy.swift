import Foundation
import WebKit

enum BrowserSiteDataPolicy {
    static func matchesDataRecord(displayName: String, host: String) -> Bool {
        let record = normalizedHost(displayName)
        let host = normalizedHost(host)
        guard !record.isEmpty, !host.isEmpty else { return false }
        return record == host
            || host.hasSuffix(".\(record)")
            || record.hasSuffix(".\(host)")
    }

    static func matchesCookieDomain(_ domain: String, host: String) -> Bool {
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
