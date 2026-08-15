import Foundation

/// What a palette row hands back to its provider when the person picks it.
///
/// The keyword travels with the content because results outlive the query that
/// produced them: a row prepared under one keyword must never be delivered to
/// whichever provider happens to be active by the time it is clicked.
struct BrowserOmniboxAcceptance: Equatable, Hashable, Sendable {
    let keyword: BrowserOmniboxKeyword
    let content: String
    let isDeletable: Bool

    init(
        keyword: BrowserOmniboxKeyword,
        content: String,
        isDeletable: Bool = false
    ) {
        self.keyword = keyword
        self.content = content
        self.isDeletable = isDeletable
    }
}
