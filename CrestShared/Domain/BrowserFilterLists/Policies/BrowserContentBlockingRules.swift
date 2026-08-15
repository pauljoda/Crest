import Foundation

enum BrowserContentBlockingRules {
    static let identifier = "com.pauldavis.crest.content-blocking.balanced.v2"

    private static let blockedHostSuffixes = [
        "doubleclick.net",
        "googleadservices.com",
        "googlesyndication.com",
        "google-analytics.com",
        "googletagmanager.com",
        "ads-twitter.com",
        "analytics.twitter.com",
        "scorecardresearch.com",
        "quantserve.com",
        "hotjar.com",
        "segment.io",
        "segment.com",
        "mixpanel.com",
        "amplitude.com",
        "clarity.ms",
        "nr-data.net",
        "taboola.com",
        "outbrain.com",
        "snap.licdn.com",
    ]

    private static let networkResourceTypes = [
        "child-document",
        "image",
        "style-sheet",
        "script",
        "font",
        "raw",
        "svg-document",
        "media",
        "popup",
        "ping",
        "fetch",
        "websocket",
        "csp-report",
        "other",
    ]

    static let balancedSource: String = {
        (try? encodedBalancedSource()) ?? "[]"
    }()

    private static func encodedBalancedSource() throws -> String {
        let rules: [[String: Any]] = blockedHostSuffixes.map { host in
            let escapedHost = host.replacingOccurrences(of: ".", with: "\\.")
            return [
                "trigger": [
                    "url-filter": "^[^:]+://+([^:/]+\\.)?\(escapedHost)[:/]",
                    "url-filter-is-case-sensitive": true,
                    "load-type": ["third-party"],
                    "resource-type": networkResourceTypes,
                ],
                "action": ["type": "block"],
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: rules)
        return String(decoding: data, as: UTF8.self)
    }
}
