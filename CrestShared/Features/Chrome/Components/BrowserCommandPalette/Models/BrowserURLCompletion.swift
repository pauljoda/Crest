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

    /// Normalized once for the palette's immutable Space snapshot. URL parsing
    /// and candidate allocation do not repeat as the user edits the address.
    struct Candidates: Sendable {
        private let values: [Candidate]

        init(space: BrowserSpace?) {
            guard let space else {
                values = []
                return
            }
            var candidates: [Candidate] = []
            for tab in space.tabs where !tab.isStartPage {
                if let url = tab.url,
                    let candidate = Candidate(
                        url: url, source: tab.placement == .current ? 3 : 2, date: tab.lastActivatedAt, visits: 0)
                {
                    candidates.append(candidate)
                }
                if tab.placement != .current, let url = tab.savedSiteURL,
                    let candidate = Candidate(url: url, source: 2, date: tab.lastActivatedAt, visits: 0)
                {
                    candidates.append(candidate)
                }
            }
            for entry in space.history.prefix(BrowserCommandPaletteResultLimits.historyScan) {
                if let candidate = Candidate(
                    url: entry.url, source: 1, date: entry.lastVisitedAt, visits: min(20, entry.visitCount))
                {
                    candidates.append(candidate)
                }
            }
            values = candidates
        }

        func proposal(query: String) -> BrowserURLCompletion? {
            guard let input = Query(query) else { return nil }
            var best: Match?
            for candidate in values {
                guard let match = candidate.match(input) else { continue }
                // An exact local address wins even if a longer candidate ranks higher.
                if match.text.lowercased() == input.lowercased { return nil }
                if best.map({ match.outranks($0) }) ?? true { best = match }
            }
            guard let best, best.text.count > input.count else { return nil }
            return BrowserURLCompletion(
                query: query, suffix: String(best.text.dropFirst(input.count)), scheme: best.candidate.scheme)
        }
    }

    private struct Query {
        let count: Int
        let lowercased: String
        let schemePrefix: String
        let hasColon: Bool
        let authority: String
        let path: String?

        init?(_ text: String) {
            count = text.count
            guard count >= 2, count <= 2_048,
                !text.contains(where: { $0.isWhitespace || $0.isNewline }),
                !text.contains("?"), !text.contains("#"), !text.contains("@")
            else { return nil }
            lowercased = text.lowercased()
            hasColon = text.contains(":")
            if text.contains("://") {
                if lowercased.hasPrefix("https://") {
                    schemePrefix = "https://"
                } else if lowercased.hasPrefix("http://") {
                    schemePrefix = "http://"
                } else {
                    return nil
                }
            } else {
                schemePrefix = ""
            }
            let typed = text.dropFirst(schemePrefix.count)
            guard typed.count >= 2 else { return nil }
            let typedAuthority = typed.prefix { $0 != "/" }
            authority = typedAuthority.lowercased()
            path = typed.contains("/") ? String(typed.dropFirst(typedAuthority.count)) : nil
        }
    }

    private struct Candidate: Sendable {
        let url: String
        let source: Int
        let date: Date
        let visits: Int
        let scheme: String
        let authority: String
        let foldedAuthority: String
        let hasPort: Bool
        let path: String
        let suffix: String

        init?(url: URL, source: Int, date: Date, visits: Int) {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
                let host = components.host, !host.isEmpty,
                components.user == nil, components.password == nil
            else { return nil }
            self.url = url.absoluteString
            self.source = source
            self.date = date
            self.visits = visits
            self.scheme = scheme
            authority = host + (components.port.map { ":\($0)" } ?? "")
            foldedAuthority = authority.lowercased()
            hasPort = components.port != nil
            path = components.percentEncodedPath
            suffix =
                (components.percentEncodedQuery.map { "?" + $0 } ?? "")
                + (components.percentEncodedFragment.map { "#" + $0 } ?? "")
        }

        func match(_ query: Query) -> Match? {
            guard query.schemePrefix.isEmpty || query.schemePrefix == "\(scheme)://",
                !query.hasColon || !query.schemePrefix.isEmpty || hasPort,
                foldedAuthority.hasPrefix(query.authority)
            else { return nil }
            if let typedPath = query.path {
                guard query.authority == foldedAuthority, path.hasPrefix(typedPath) else { return nil }
            }
            let displayPath = path == "/" && query.path == nil && suffix.isEmpty ? "" : path
            let text = query.schemePrefix + authority + displayPath + suffix
            guard text.count >= query.count else { return nil }
            return Match(
                candidate: self, text: text,
                quality: query.path != nil ? 3 : (query.authority == foldedAuthority ? 2 : 1))
        }
    }

    private struct Match {
        let candidate: Candidate
        let text: String
        let quality: Int

        func outranks(_ other: Self) -> Bool {
            if quality != other.quality { return quality > other.quality }
            if candidate.source != other.candidate.source { return candidate.source > other.candidate.source }
            if candidate.date != other.candidate.date { return candidate.date > other.candidate.date }
            if candidate.visits != other.candidate.visits { return candidate.visits > other.candidate.visits }
            if text != other.text { return text < other.text }
            return candidate.url < other.candidate.url
        }
    }
}
