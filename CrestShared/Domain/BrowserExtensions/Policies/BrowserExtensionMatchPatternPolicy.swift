import Foundation

/// Chrome's match-pattern grammar, evaluated over a URL.
///
/// The page-world `chrome.runtime` alias
/// (`BrowserExtensionWebPageRuntimeBridge`) already carries this grammar in
/// JavaScript so a frame can decide for itself whether it is externally
/// connectable. When that frame's message is relayed through Crest instead of
/// WebKit, the same decision has to be made again on the Swift side — a page
/// can reach the relay's message handler directly, and its own claim about
/// which extension it may talk to is not evidence. Both implementations follow
/// the same rules so the two answers cannot drift:
///
/// - `<all_urls>` covers the web schemes Chrome lists for it.
/// - A `*` scheme means `http` or `https` only.
/// - A `*` host matches every host; a `*.` prefix matches the suffix itself
///   and any subdomain of it, never a host that merely ends with those
///   characters.
/// - The path glob is matched against the path *and* query together, which is
///   what Chrome does and what an OAuth hand-back URL depends on.
enum BrowserExtensionMatchPatternPolicy {
    static let allURLsPattern = "<all_urls>"
    static let allURLsSchemes: Set<String> = [
        "http", "https", "ws", "wss", "ftp", "file",
    ]
    private static let patternSchemes: Set<String> = [
        "http", "https", "ws", "wss", "ftp", "file",
    ]

    static func matches(url: URL, anyOf patterns: [String]) -> Bool {
        patterns.contains { matches(url: url, pattern: $0) }
    }

    static func matches(url: URL, pattern: String) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed == allURLsPattern {
            return allURLsSchemes.contains(scheme)
        }
        guard let parsed = parse(trimmed) else { return false }
        if parsed.scheme == "*" {
            guard scheme == "http" || scheme == "https" else { return false }
        } else if parsed.scheme != scheme {
            return false
        }
        guard matchesHost(url.host?.lowercased() ?? "", pattern: parsed.host)
        else { return false }
        return matchesGlob(pathAndQuery(of: url)[...], glob: parsed.path[...])
    }

    /// The path and query exactly as they were written, which is what the
    /// page-world alias reads off `location`. `URL.path` percent-decodes and
    /// would let an encoded separator slip past a glob.
    private static func pathAndQuery(of url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.percentEncodedPath ?? url.path
        let query = components?.percentEncodedQuery
        return (path.isEmpty ? "/" : path) + (query.map { "?" + $0 } ?? "")
    }

    private static func matchesHost(_ host: String, pattern: String) -> Bool {
        guard pattern != "*" else { return true }
        guard pattern.hasPrefix("*.") else { return host == pattern }
        let suffix = String(pattern.dropFirst(2))
        return host == suffix || host.hasSuffix("." + suffix)
    }

    private struct ParsedPattern {
        let scheme: String
        let host: String
        let path: String
    }

    private static func parse(_ pattern: String) -> ParsedPattern? {
        guard let separator = pattern.range(of: "://") else { return nil }
        let scheme = String(pattern[pattern.startIndex..<separator.lowerBound])
            .lowercased()
        guard scheme == "*" || patternSchemes.contains(scheme) else {
            return nil
        }
        let remainder = pattern[separator.upperBound...]
        guard let pathStart = remainder.firstIndex(of: "/") else { return nil }
        let host = String(remainder[remainder.startIndex..<pathStart])
            .lowercased()
        // A host is `*`, `*.<suffix>`, or a literal host. A `*` anywhere else
        // is not a legal host in this grammar.
        if host != "*", host.contains("*") {
            guard host.hasPrefix("*."), !host.dropFirst(2).contains("*") else {
                return nil
            }
        }
        return ParsedPattern(
            scheme: scheme,
            host: host,
            path: String(remainder[pathStart...])
        )
    }

    /// `*` is the only wildcard in a match pattern's path, and it matches any
    /// run of characters including none.
    private static func matchesGlob(
        _ value: Substring,
        glob: Substring
    ) -> Bool {
        let segments = glob.split(
            separator: "*",
            omittingEmptySubsequences: false
        )
        guard let first = segments.first, let last = segments.last,
            segments.count > 1
        else { return value == glob }
        guard value.hasPrefix(first), value.hasSuffix(last),
            value.count >= first.count + last.count
        else { return false }
        var remainder = value.dropFirst(first.count).dropLast(last.count)
        for segment in segments[1..<(segments.count - 1)] {
            guard !segment.isEmpty else { continue }
            guard let found = remainder.range(of: segment) else { return false }
            remainder = remainder[found.upperBound...]
        }
        return true
    }
}
