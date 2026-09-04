import Foundation

/// Reads the `externally_connectable.matches` patterns an extension authors.
///
/// WebKit gives every web page in a Space with extensions a `browser.runtime`
/// and checks these patterns only when the page sends a message. Crest reads
/// them up front so the page-world `chrome.runtime` alias appears exactly on
/// the frames Chrome would expose it to, and nowhere else.
enum BrowserExtensionExternallyConnectablePolicy {
    static func matchPatterns(in manifest: [String: Any]) -> [String] {
        guard let section = manifest["externally_connectable"] as? [String: Any],
            let matches = section["matches"] as? [Any]
        else { return [] }
        var seen = Set<String>()
        var patterns: [String] = []
        for case let pattern as String in matches {
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            patterns.append(trimmed)
        }
        return patterns
    }
}
