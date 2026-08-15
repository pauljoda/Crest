import Foundation

struct BrowserFaviconTaskIdentity: Hashable, Sendable {
    let tabID: TabID
    let profileID: UUID?
    let pageURL: URL?
    let iconMode: String
    let payload: BrowserFaviconPayloadIdentity?
    let maximumPixelSize: Int
}
