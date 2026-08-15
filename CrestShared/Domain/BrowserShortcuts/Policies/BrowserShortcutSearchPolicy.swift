import Foundation

enum BrowserShortcutSearchPolicy {
    static func matches(query: String, fields: [String]) -> Bool {
        let terms =
            query
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return true }

        let haystack = fields.joined(separator: " ").lowercased()
        let haystackTerms = haystack.split {
            !$0.isLetter && !$0.isNumber
        }
        return terms.allSatisfy { term in
            guard term.count == 1 else { return haystack.contains(term) }
            return haystackTerms.contains(term)
        }
    }

    static func matches(
        query: String,
        document: BrowserShortcutSearchDocument
    ) -> Bool {
        matches(query: query, fields: document.fields)
    }

    static func containsTrimmedPhrase(
        query: String,
        fields: [String]
    ) -> Bool {
        let phrase = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        guard !phrase.isEmpty else { return true }
        return fields.joined(separator: " ").lowercased().contains(phrase)
    }
}
