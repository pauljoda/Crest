import Foundation

enum BrowserFaviconTaskIdentityPolicy {
    static func identity(
        for tab: BrowserTab,
        profileID: UUID?,
        maximumPixelSize: Int,
        isUnlocked: Bool = true
    ) -> BrowserFaviconTaskIdentity {
        BrowserFaviconTaskIdentity(
            tabID: tab.id,
            profileID: profileID,
            pageURL: tab.url,
            iconMode: tab.iconMode.name,
            // The tab already fingerprinted its own payload. SwiftUI evaluates
            // this identity during every view update, so nothing here may read
            // the image bytes.
            payload: tab.displayFaviconPayloadIdentity,
            maximumPixelSize: maximumPixelSize,
            isUnlocked: isUnlocked
        )
    }

    /// A locked Space must never reach the network for an icon: the request that
    /// fetches `https://<host>/favicon.ico` would disclose the hostnames the lock
    /// exists to hide, and would cache them under the locked Space's profile.
    /// Redaction is a drawing effect and cannot stop that, so the fallback is
    /// dropped at the request itself.
    static func renderRequest(
        for tab: BrowserTab,
        profileID: UUID?,
        maximumPixelSize: Int,
        isUnlocked: Bool = true
    ) -> BrowserFaviconRenderRequest {
        let identity = identity(
            for: tab,
            profileID: profileID,
            maximumPixelSize: maximumPixelSize,
            isUnlocked: isUnlocked
        )
        guard !tab.isStartPage, tab.emojiIcon == nil, isUnlocked else {
            return BrowserFaviconRenderRequest(
                identity: identity,
                payload: nil,
                fallbackPageURL: nil,
                fallbackProfileID: nil
            )
        }

        let payload = tab.displayFaviconData
        return BrowserFaviconRenderRequest(
            identity: identity,
            payload: payload,
            fallbackPageURL: payload == nil ? tab.url : nil,
            fallbackProfileID: payload == nil ? profileID : nil
        )
    }
}
