import CoreGraphics

struct BrowserFaviconImageCacheRequestLease: Sendable {
    let token: BrowserFaviconImageCacheRequestToken
    let task: Task<CGImage?, Never>
}
