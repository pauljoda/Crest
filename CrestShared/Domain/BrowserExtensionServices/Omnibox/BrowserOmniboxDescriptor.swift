import Foundation

/// How a registered suggestion provider presents itself in the palette.
struct BrowserOmniboxDescriptor: Equatable, Hashable, Sendable {
    let keyword: BrowserOmniboxKeyword
    /// The provider's display name, shown on the keyword-mode row.
    let title: String
    /// The line shown before the provider has offered anything, and the row
    /// that submits the raw query. Backs `chrome.omnibox.setDefaultSuggestion`.
    let defaultSuggestionDescription: String
}
