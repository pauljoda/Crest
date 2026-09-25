import Foundation

enum BrowserFaviconTaskIdentityPolicy {
    static func identity(
        for subject: BrowserTabFaviconSubject,
        profileID: UUID?,
        maximumPixelSize: Int,
        isUnlocked: Bool = true
    ) -> BrowserFaviconTaskIdentity {
        BrowserFaviconTaskIdentity(
            tabID: subject.tabID,
            profileID: profileID,
            pageURL: subject.pageURL,
            iconMode: subject.iconMode.name,
            // The image carries the fingerprint taken when it was set. SwiftUI
            // evaluates this identity during every view update, so nothing
            // here may read the image bytes.
            payload: subject.image?.identity,
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
        for subject: BrowserTabFaviconSubject,
        profileID: UUID?,
        maximumPixelSize: Int,
        isUnlocked: Bool = true
    ) -> BrowserFaviconRenderRequest {
        let identity = identity(
            for: subject,
            profileID: profileID,
            maximumPixelSize: maximumPixelSize,
            isUnlocked: isUnlocked
        )
        guard !subject.isStartPage, subject.emoji == nil, isUnlocked else {
            return BrowserFaviconRenderRequest(
                identity: identity,
                payload: nil,
                fallbackPageURL: nil,
                fallbackProfileID: nil
            )
        }

        let payload = subject.image?.data
        return BrowserFaviconRenderRequest(
            identity: identity,
            payload: payload,
            fallbackPageURL: payload == nil ? subject.pageURL : nil,
            fallbackProfileID: payload == nil ? profileID : nil
        )
    }

    static func identity(
        for tab: BrowserTab,
        profileID: UUID?,
        maximumPixelSize: Int,
        isUnlocked: Bool = true
    ) -> BrowserFaviconTaskIdentity {
        identity(
            for: BrowserTabFaviconSubject(tab: tab), profileID: profileID, maximumPixelSize: maximumPixelSize,
            isUnlocked: isUnlocked)
    }

    static func renderRequest(
        for tab: BrowserTab,
        profileID: UUID?,
        maximumPixelSize: Int,
        isUnlocked: Bool = true
    ) -> BrowserFaviconRenderRequest {
        renderRequest(
            for: BrowserTabFaviconSubject(tab: tab), profileID: profileID, maximumPixelSize: maximumPixelSize,
            isUnlocked: isUnlocked)
    }
}
