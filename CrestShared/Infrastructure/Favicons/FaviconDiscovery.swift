import Foundation

struct BrowserFaviconDiscovery: Equatable, Sendable {
    let iconURLs: [URL]
    let manifestURLs: [URL]
    let userAgent: String?
}
