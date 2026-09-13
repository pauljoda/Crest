import Foundation

struct BrowserFaviconCapturePolicy: Sendable {
    let retryDelays: [Duration]

    static let immediate = Self(retryDelays: [])
    static let delayedDocumentIcons = Self(retryDelays: [.milliseconds(500), .seconds(2)])
}
