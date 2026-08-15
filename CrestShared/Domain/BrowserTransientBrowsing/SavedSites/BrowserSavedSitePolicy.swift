import Foundation

enum BrowserSavedSitePolicy {
    static func isSameSite(_ first: URL, _ second: URL) -> Bool {
        normalizedHost(first) == normalizedHost(second)
    }

    static func normalizedHost(_ url: URL) -> String? {
        guard var host = url.host(percentEncoded: false)?.lowercased(),
              !host.isEmpty else { return nil }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host
    }
}
