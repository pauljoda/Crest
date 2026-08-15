import Foundation

/// Address-bar text split into a provider keyword and the query that follows.
struct BrowserOmniboxInput: Equatable, Hashable, Sendable {
    let keyword: BrowserOmniboxKeyword
    /// Everything after the keyword, with the separating whitespace removed.
    /// Empty right after the person types the keyword and a space.
    let query: String

    /// Splits `text` at its first run of whitespace.
    ///
    /// Keyword mode needs that separator to exist: `"yt"` on its own is still a
    /// plain search for the letters, and only `"yt "` hands the address bar
    /// over. That matches Chrome, and it keeps a keyword from hijacking a
    /// prefix the person is still in the middle of typing.
    static func parse(_ text: String) -> BrowserOmniboxInput? {
        let leadingTrimmed = text.drop(while: \.isWhitespace)
        guard let separator = leadingTrimmed.firstIndex(where: \.isWhitespace)
        else {
            return nil
        }

        guard
            let keyword = BrowserOmniboxKeyword(
                String(leadingTrimmed[..<separator])
            )
        else {
            return nil
        }

        let remainder = leadingTrimmed[separator...].drop(while: \.isWhitespace)
        return BrowserOmniboxInput(keyword: keyword, query: String(remainder))
    }
}
