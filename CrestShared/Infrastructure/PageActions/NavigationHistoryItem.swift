import Foundation

struct BrowserNavigationHistoryItem: Identifiable, Equatable, Sendable {
    let depth: Int
    let title: String
    let url: URL

    var id: Int { depth }
}
