import Foundation

/// Which `modifyHeaders` header names WebKit accepts, and which ones a
/// JavaScript `fetch` may still not send once Crest has taken them over.
///
/// Both tables are also serialized into the compatibility runtime, so the
/// partition the runtime performs and the partition described here can never
/// be two different lists.
enum BrowserExtensionDeclarativeNetRequestHeaderPolicy {
    /// `isHeaderNameValid`'s `acceptedHeaderNames`, copied verbatim from
    /// WebKit's `Source/WebKit/UIProcess/Extensions/Cocoa/API/
    /// _WKWebExtensionDeclarativeNetRequestRule.mm` at the matrix's pinned
    /// WebKit revision, in the same order.
    ///
    /// WebKit compares `headerName.lowercaseString` against this list and
    /// rejects the *entire rule* — "Rule with id N is invalid. The header `X`
    /// is not recognized." — when a name is missing, so a rule carrying one
    /// custom header loses its standard headers too. This is why Crest
    /// partitions a rule instead of forwarding it whole.
    static let webKitAcceptedHeaderNames: [String] = [
        "accept",
        "accept-charset",
        "accept-language",
        "accept-encoding",
        "accept-ranges",
        "access-control-allow-credentials",
        "access-control-allow-headers",
        "access-control-allow-methods",
        "access-control-allow-origin",
        "access-control-expose-headers",
        "access-control-max-age",
        "access-control-request-headers",
        "access-control-request-method",
        "age",
        "authorization",
        "cache-control",
        "connection",
        "content-disposition",
        "content-encoding",
        "content-language",
        "content-length",
        "content-location",
        "content-security-policy",
        "content-security-policy-report-only",
        "content-type",
        "content-range",
        "cookie",
        "cookie2",
        "cross-origin-embedder-policy",
        "cross-origin-embedder-policy-report-only",
        "cross-origin-opener-policy",
        "cross-origin-opener-policy-report-only",
        "cross-origin-resource-policy",
        "date",
        "dnt",
        "default-style",
        "etag",
        "expect",
        "expires",
        "host",
        "if-match",
        "if-modified-since",
        "if-none-match",
        "if-range",
        "if-unmodified-since",
        "keep-alive",
        "last-event-id",
        "last-modified",
        "link",
        "location",
        "origin",
        "ping-from",
        "ping-to",
        "purpose",
        "pragma",
        "proxy-authorization",
        "range",
        "referer",
        "referrer-policy",
        "refresh",
        "report-to",
        "reporting-endpoints",
        "sec-fetch-dest",
        "sec-fetch-mode",
        "sec-gpc",
        "sec-websocket-accept",
        "sec-websocket-extensions",
        "sec-websocket-key",
        "sec-websocket-protocol",
        "sec-websocket-version",
        "server-timing",
        "service-worker",
        "service-worker-allowed",
        "service-worker-navigation-preload",
        "set-cookie",
        "set-cookie2",
        "sourcemap",
        "te",
        "timing-allow-origin",
        "trailer",
        "transfer-encoding",
        "upgrade",
        "upgrade-insecure-requests",
        "user-agent",
        "vary",
        "via",
        "x-content-type-options",
        "x-frame-options",
        "x-sourcemap",
        "x-xss-protection",
        "x-temp-tablet",
        "icy-metaint",
        "icy-metadata",
    ]

    private static let acceptedHeaderNameSet = Set(webKitAcceptedHeaderNames)

    /// Whether WebKit's own `modifyHeaders` validation accepts this name.
    static func webKitAcceptsHeaderName(_ name: String) -> Bool {
        acceptedHeaderNameSet.contains(name.lowercased())
    }

    /// Header names the Fetch standard forbids a script from setting.
    ///
    /// Chrome applies a `modifyHeaders` rule inside the network stack, below
    /// this restriction. Crest applies it from JavaScript, above it, so these
    /// names are reported as skipped rather than silently dropped. `User-Agent`
    /// is the consequential one: an extension cannot change it from `fetch`.
    static let fetchForbiddenHeaderNames: [String] = [
        "accept-charset",
        "accept-encoding",
        "access-control-request-headers",
        "access-control-request-method",
        "connection",
        "content-length",
        "cookie",
        "cookie2",
        "date",
        "dnt",
        "expect",
        "host",
        "keep-alive",
        "origin",
        "referer",
        "set-cookie",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade",
        "user-agent",
        "via",
    ]

    /// Forbidden name *prefixes*, matched case-insensitively.
    static let fetchForbiddenHeaderNamePrefixes: [String] = ["proxy-", "sec-"]

    private static let forbiddenHeaderNameSet = Set(fetchForbiddenHeaderNames)

    /// Whether a script may set this header on a `fetch` or `XMLHttpRequest`.
    static func fetchForbidsHeaderName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        if forbiddenHeaderNameSet.contains(lowered) { return true }
        return fetchForbiddenHeaderNamePrefixes.contains { lowered.hasPrefix($0) }
    }

    /// Splits one rule's `requestHeaders` into the half WebKit will accept and
    /// the half Crest has to emulate.
    static func partition(
        requestHeaders: [BrowserExtensionEmulatedHeaderRule.HeaderModification]
    ) -> (
        accepted: [BrowserExtensionEmulatedHeaderRule.HeaderModification],
        emulated: [BrowserExtensionEmulatedHeaderRule.HeaderModification]
    ) {
        var accepted: [BrowserExtensionEmulatedHeaderRule.HeaderModification] = []
        var emulated: [BrowserExtensionEmulatedHeaderRule.HeaderModification] = []
        for modification in requestHeaders {
            if webKitAcceptsHeaderName(modification.header) {
                accepted.append(modification)
            } else {
                emulated.append(modification)
            }
        }
        return (accepted, emulated)
    }
}
