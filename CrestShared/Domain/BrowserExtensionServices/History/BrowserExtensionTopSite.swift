import Foundation

/// One `chrome.topSites` entry.
struct BrowserExtensionTopSite: Equatable, Hashable, Identifiable, Sendable {
    let url: URL
    let title: String

    var id: URL { url }

    init(url: URL, title: String) {
        self.url = url
        self.title = title
    }
}
