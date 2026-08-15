import Foundation

/// One `chrome.history.VisitItem`.
///
/// Crest keeps a single row per URL carrying `firstVisitedAt`, `lastVisitedAt`,
/// and a count — it does not journal individual visits. A URL therefore reports
/// at most the two visits Crest can actually attest to, even when its visit
/// count is far higher. Extensions that reconstruct a session timeline from
/// `getVisits` will see the endpoints rather than every intermediate visit.
struct BrowserExtensionHistoryVisit: Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let url: URL
    let visitTime: Date
    let transition: BrowserExtensionHistoryTransition

    init(
        id: String,
        url: URL,
        visitTime: Date,
        transition: BrowserExtensionHistoryTransition = .link
    ) {
        self.id = id
        self.url = url
        self.visitTime = visitTime
        self.transition = transition
    }
}
