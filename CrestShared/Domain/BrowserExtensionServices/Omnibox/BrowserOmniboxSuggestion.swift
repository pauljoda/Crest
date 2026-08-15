import Foundation

/// One row a suggestion provider offered for the current query.
struct BrowserOmniboxSuggestion: Equatable, Hashable, Sendable {
    /// The opaque value handed back to the provider on acceptance. Chrome
    /// treats this as the text the address bar would contain.
    let content: String
    /// The line shown to the person.
    ///
    /// Chrome allows a small XML dialect here for match highlighting; Crest
    /// renders the text plainly, so a provider should send plain text.
    let description: String
    /// Whether the person may remove this row from the provider's own history.
    let isDeletable: Bool

    init(content: String, description: String, isDeletable: Bool = false) {
        self.content = content
        self.description = description
        self.isDeletable = isDeletable
    }
}
