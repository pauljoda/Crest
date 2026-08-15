import Foundation

struct BrowserFaviconRenderRequest: Sendable {
    let identity: BrowserFaviconTaskIdentity
    let payload: Data?
    let fallbackPageURL: URL?
    let fallbackProfileID: UUID?
}
