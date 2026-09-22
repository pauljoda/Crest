import Foundation

enum BrowserHistoryURL {
    static func normalized(_ url: URL) -> URL? {
        return BrowserCorePolicy.normalizedHistoryURL(url)
    }
}
