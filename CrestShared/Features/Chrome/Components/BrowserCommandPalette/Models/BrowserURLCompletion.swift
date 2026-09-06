import Foundation

/// A local proposal. Neither the editor's text nor the result list includes it.
struct BrowserURLCompletion: Equatable, Sendable {
    let query: String
    let suffix: String
    let scheme: String

    var completedQuery: String { query + suffix }
    var acceptedQuery: String {
        query.contains("://") || scheme == "https" ? completedQuery : "\(scheme)://\(completedQuery)"
    }
    var insertionText: String { acceptedQuery == completedQuery ? suffix : acceptedQuery }
    var insertionRange: NSRange {
        acceptedQuery == completedQuery
            ? NSRange(location: query.utf16.count, length: 0)
            : NSRange(location: 0, length: query.utf16.count)
    }

    static func proposal(query: String, space: BrowserSpace?) -> Self? {
        guard let space, query.count >= 2, query.count <= 2_048,
            !query.contains(where: { $0.isWhitespace || $0.isNewline }),
            !query.contains("?"), !query.contains("#"), !query.contains("@")
        else { return nil }

        var candidates: [Candidate] = []
        for tab in space.tabs where !tab.isStartPage {
            if let url = tab.url {
                candidates.append(
                    Candidate(url: url, source: tab.placement == .current ? 3 : 2, date: tab.lastActivatedAt, visits: 0)
                )
            }
            if tab.placement != .current, let url = tab.savedSiteURL {
                candidates.append(Candidate(url: url, source: 2, date: tab.lastActivatedAt, visits: 0))
            }
        }
        for entry in space.history.prefix(BrowserCommandPaletteResultLimits.historyScan) {
            candidates.append(
                Candidate(url: entry.url, source: 1, date: entry.lastVisitedAt, visits: min(20, entry.visitCount)))
        }
        var matches: [(candidate: Candidate, text: String, quality: Int)] = []
        for candidate in candidates {
            guard let match = candidate.match(query: query) else { continue }
            // An address already present locally has no missing suffix to suggest.
            if match.text == query || match.text.lowercased() == query.lowercased() { return nil }
            matches.append((candidate, match.text, match.quality))
        }
        let best = matches.sorted {
            if $0.quality != $1.quality { return $0.quality > $1.quality }
            if $0.candidate.source != $1.candidate.source { return $0.candidate.source > $1.candidate.source }
            if $0.candidate.date != $1.candidate.date { return $0.candidate.date > $1.candidate.date }
            if $0.candidate.visits != $1.candidate.visits { return $0.candidate.visits > $1.candidate.visits }
            if $0.text != $1.text { return $0.text < $1.text }
            return $0.candidate.url.absoluteString < $1.candidate.url.absoluteString
        }.first
        guard let best, best.text.count > query.count, let scheme = best.candidate.url.scheme else { return nil }
        return Self(
            query: query, suffix: String(best.text.dropFirst(query.count)),
            scheme: scheme.lowercased())
    }

    private struct Candidate {
        let url: URL
        let source: Int
        let date: Date
        let visits: Int

        func match(query: String) -> (text: String, quality: Int)? {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
                let host = components.host, !host.isEmpty,
                components.user == nil, components.password == nil
            else { return nil }
            let explicitScheme = query.contains("://")
            if query.contains(":"), !explicitScheme, components.port == nil { return nil }
            let prefix = explicitScheme ? "\(scheme)://" : ""
            guard !explicitScheme || query.lowercased().hasPrefix(prefix) else { return nil }
            let typed = explicitScheme ? String(query.dropFirst(prefix.count)) : query
            guard typed.count >= 2 else { return nil }
            let authority = host + (components.port.map { ":\($0)" } ?? "")
            let path = components.percentEncodedPath
            let querySuffix = components.percentEncodedQuery.map { "?" + $0 } ?? ""
            let fragmentSuffix = components.percentEncodedFragment.map { "#" + $0 } ?? ""
            let displayPath =
                path == "/" && !typed.contains("/") && querySuffix.isEmpty && fragmentSuffix.isEmpty ? "" : path
            let text = prefix + authority + displayPath + querySuffix + fragmentSuffix
            let typedAuthority = String(typed.prefix { $0 != "/" })
            guard authority.lowercased().hasPrefix(typedAuthority.lowercased()) else { return nil }
            if typed.contains("/") {
                guard typedAuthority.lowercased() == authority.lowercased(),
                    (authority + path).dropFirst(authority.count).hasPrefix(typed.dropFirst(typedAuthority.count))
                else { return nil }
            }
            guard text.count >= query.count else { return nil }
            return (text, typed.contains("/") ? 3 : (typedAuthority.lowercased() == authority.lowercased() ? 2 : 1))
        }
    }
}
