import Foundation

enum BrowserFaviconTaskIdentityPolicy {
    static func identity(
        for tab: BrowserTab,
        profileID: UUID?,
        maximumPixelSize: Int
    ) -> BrowserFaviconTaskIdentity {
        BrowserFaviconTaskIdentity(
            tabID: tab.id,
            profileID: profileID,
            pageURL: tab.url,
            iconMode: tab.iconMode.rawValue,
            // The tab already fingerprinted its own payload. SwiftUI evaluates
            // this identity during every view update, so nothing here may read
            // the image bytes.
            payload: tab.displayFaviconPayloadIdentity,
            maximumPixelSize: maximumPixelSize
        )
    }

    static func renderRequest(
        for tab: BrowserTab,
        profileID: UUID?,
        maximumPixelSize: Int
    ) -> BrowserFaviconRenderRequest {
        let identity = identity(
            for: tab,
            profileID: profileID,
            maximumPixelSize: maximumPixelSize
        )
        guard !tab.isStartPage, tab.emojiIcon == nil else {
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
