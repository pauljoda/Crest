import Foundation

enum BrowserExternalLinkScenePolicy {
    /// Existing browser windows claim external links so SwiftUI doesn't create
    /// another primary window just to deliver the URL.
    static let existingBrowserPreference: Set<String> = ["*"]

    /// The primary browser remains the ordinary launch scene, but it is never
    /// materialized as the fallback destination for an external URL.
    static let primarySceneActivation: Set<String> = []

    /// With no browser window open, the dedicated transient scene receives the
    /// URL and can stay as the app's only visible window until promotion.
    static let quickWindowSceneActivation: Set<String> = ["*"]
}
