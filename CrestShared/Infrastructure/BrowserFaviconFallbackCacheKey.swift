import Foundation

struct BrowserFaviconFallbackCacheKey: Hashable, Sendable {
    let profileID: UUID
    let iconURL: URL
}
