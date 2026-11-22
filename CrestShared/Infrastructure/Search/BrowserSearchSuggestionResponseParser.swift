import Foundation

/// Reads the suggestions an engine sends in the OpenSearch suggestions form:
/// the query, then an array of suggestions, then fields the palette does not
/// use. Anything else, or a reply larger than the client reads, gives none.
enum BrowserSearchSuggestionResponseParser {
    // MARK: - Static Variables

    /// The most suggestions the palette takes from one reply.
    static let maximumSuggestions = 20

    // MARK: - Types

    /// One reply, keeping only the suggestions that are text.
    private struct Reply: Decodable {
        let suggestions: [String]

        init(from decoder: any Decoder) throws {
            var reply = try decoder.unkeyedContainer()
            _ = try reply.decode(Ignored.self)
            var list = try reply.nestedUnkeyedContainer()
            var suggestions: [String] = []
            while !list.isAtEnd {
                if let text = try? list.decode(String.self) {
                    suggestions.append(text)
                } else {
                    _ = try list.decode(Ignored.self)
                }
            }
            self.suggestions = suggestions
        }
    }

    /// A value of any kind the reply holds and the palette skips.
    private struct Ignored: Decodable {
        init(from decoder: any Decoder) throws {}
    }

    // MARK: - Actions - Parsing

    static func suggestions(from data: Data) -> [String] {
        guard data.count <= BrowserSearchSuggestionClient.maximumResponseByteCount,
            let reply = try? JSONDecoder().decode(Reply.self, from: data)
        else { return [] }
        return Array(reply.suggestions.prefix(maximumSuggestions))
    }
}
