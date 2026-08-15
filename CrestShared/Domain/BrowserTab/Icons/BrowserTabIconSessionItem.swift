import Foundation

struct BrowserTabIconSessionItem: Equatable, Sendable {
    let id: TabID
    let url: URL?
    let faviconData: Data?
    let faviconURL: URL?
    let iconAccent: BrowserTabIconAccent?
    let iconMode: BrowserTabIconMode
    let symbol: String
}
