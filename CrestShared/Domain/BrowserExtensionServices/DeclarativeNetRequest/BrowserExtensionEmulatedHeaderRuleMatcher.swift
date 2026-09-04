import Foundation

/// Chrome's `declarativeNetRequest` condition matching, as Crest applies it.
///
/// This is the reference implementation of the grammar. The compatibility
/// runtime mirrors it in JavaScript because the decision has to be made in the
/// context that issues the request, and the two are pinned by the same test
/// cases: `urlFilter`'s anchors, wildcard, and separator; `regexFilter`;
/// resource types; request methods; and which rule wins when several change
/// the same header.
enum BrowserExtensionEmulatedHeaderRuleMatcher {
    /// The resource type Crest reports for `fetch` and `XMLHttpRequest`.
    static let scriptRequestResourceType = "xmlhttprequest"

    /// Chrome treats a request whose type it cannot classify as `other`, and
    /// packages routinely list both. A rule that names neither is not about
    /// the traffic this emulation can reach.
    static let acceptedResourceTypes: Set<String> = [scriptRequestResourceType, "other"]

    /// Whether one rule's condition matches a request the extension is making.
    static func matches(
        _ condition: BrowserExtensionEmulatedHeaderRule.Condition,
        url: String,
        method: String
    ) -> Bool {
        if let resourceTypes = condition.resourceTypes {
            guard !acceptedResourceTypes.isDisjoint(with: resourceTypes) else { return false }
        }
        if let excluded = condition.excludedResourceTypes,
            excluded.contains(scriptRequestResourceType)
        {
            return false
        }
        let normalizedMethod = method.lowercased()
        if let methods = condition.requestMethods, !methods.contains(normalizedMethod) {
            return false
        }
        if let excluded = condition.excludedRequestMethods, excluded.contains(normalizedMethod) {
            return false
        }
        if let regexFilter = condition.regexFilter {
            guard
                matchesRegularExpression(
                    regexFilter, url: url, isCaseSensitive: condition.isURLFilterCaseSensitive)
            else { return false }
        }
        if let urlFilter = condition.urlFilter, !urlFilter.isEmpty {
            guard
                matchesRegularExpression(
                    urlFilterExpression(urlFilter), url: url,
                    isCaseSensitive: condition.isURLFilterCaseSensitive)
            else { return false }
        }
        return true
    }

    /// The header operations that survive when every matching rule has had its
    /// say.
    ///
    /// One operation wins per header name: the highest `priority`, and among
    /// equal priorities the lowest rule id. The result is ordered by header
    /// name so a trace of it is stable.
    static func modifications(
        applying rules: [BrowserExtensionEmulatedHeaderRule],
        url: String,
        method: String
    ) -> [BrowserExtensionEmulatedHeaderRule.HeaderModification] {
        var winners: [String: (rule: BrowserExtensionEmulatedHeaderRule, index: Int)] = [:]
        var chosen: [String: BrowserExtensionEmulatedHeaderRule.HeaderModification] = [:]
        for (index, rule) in rules.enumerated() {
            guard matches(rule.condition, url: url, method: method) else { continue }
            for modification in rule.requestHeaders {
                let name = modification.header.lowercased()
                if let existing = winners[name] {
                    let outranks =
                        rule.priority > existing.rule.priority
                        || (rule.priority == existing.rule.priority
                            && rule.id < existing.rule.id)
                    guard outranks else { continue }
                }
                winners[name] = (rule, index)
                chosen[name] = modification
            }
        }
        return chosen.keys.sorted().compactMap { chosen[$0] }
    }

    /// Chrome's `urlFilter` grammar, translated to a regular expression.
    ///
    /// - `||` at the start anchors to the start of a host or of any of its
    ///   parent-labelled subdomains.
    /// - `|` at the start or end anchors to the start or end of the URL.
    /// - `*` spans any run of characters.
    /// - `^` is a separator: any character that is not a letter, digit, `_`,
    ///   `-`, `.`, or `%`, or the end of the URL.
    /// - Every other character is literal.
    static func urlFilterExpression(_ urlFilter: String) -> String {
        var characters = Array(urlFilter)
        var expression = ""
        var index = 0
        if characters.first == "|" {
            if characters.count > 1 && characters[1] == "|" {
                // Host anchor: the scheme, then optionally any run of
                // dot-terminated subdomain labels.
                expression += "^[^:/?#]+://(?:[^/?#]*\\.)?"
                index = 2
            } else {
                expression += "^"
                index = 1
            }
        }
        var anchorsEnd = false
        if characters.count > index, characters.last == "|" {
            anchorsEnd = true
            characters.removeLast()
        }
        while index < characters.count {
            let character = characters[index]
            switch character {
            case "*":
                expression += ".*"
            case "^":
                expression += "(?:[^A-Za-z0-9_\\-.%]|$)"
            default:
                expression += NSRegularExpression.escapedPattern(for: String(character))
            }
            index += 1
        }
        if anchorsEnd { expression += "$" }
        return expression
    }

    private static func matchesRegularExpression(
        _ pattern: String, url: String, isCaseSensitive: Bool
    ) -> Bool {
        // An extension can author a pattern WebKit's engine rejects. Chrome
        // discards such a rule; matching nothing is the same outcome without a
        // thrown error reaching the request.
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern, options: isCaseSensitive ? [] : [.caseInsensitive])
        else { return false }
        return expression.firstMatch(
            in: url, range: NSRange(url.startIndex..<url.endIndex, in: url)) != nil
    }
}
