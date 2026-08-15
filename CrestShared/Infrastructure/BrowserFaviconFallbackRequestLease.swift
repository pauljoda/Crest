import Foundation

struct BrowserFaviconFallbackRequestLease: Sendable {
    let token: BrowserFaviconFallbackRequestToken
    let task: Task<Data?, Never>
}
