import Foundation

struct BrowserNavigationHistoryItem: Identifiable, Equatable, Sendable {
    // MARK: - Static Variables

    /// The most entries one direction of a page's history lists, nearest first,
    /// as Chromium's back and forward menus do. Farther entries stay a Back or
    /// Forward away, and History keeps every visit.
    static let listedLimit = 12

    // MARK: - Variables

    let depth: Int
    let title: String
    let url: URL

    var id: Int { depth }
}
