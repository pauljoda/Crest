import Foundation

/// A history change observed for one Space.
///
/// Backs `chrome.history.onVisited` and `chrome.history.onVisitRemoved`.
enum BrowserExtensionHistoryChange: Equatable, Hashable, Sendable {
    /// A URL was visited for the first time, or an existing entry gained a
    /// visit. Carries the entry as it now stands.
    case visited(BrowserExtensionHistoryItem)
    /// Specific URLs left the Space's history.
    case removed(urls: [URL])
    /// The Space's entire history was cleared.
    case removedAll
}
