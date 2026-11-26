import CoreGraphics
import Foundation

enum BrowserFaviconRenderLoader {
    /// Returns a decoded icon synchronously when `request` carries a payload
    /// whose fingerprint is already cached.
    static func cachedImage(for request: BrowserFaviconRenderRequest) -> CGImage? {
        guard request.payload != nil, let payloadIdentity = request.identity.payload else { return nil }
        return BrowserFaviconImageCache.shared.cachedImage(
            for: payloadIdentity,
            maximumPixelSize: request.identity.maximumPixelSize
        )
    }

    static func decode(
        _ request: BrowserFaviconRenderRequest,
        fallbackData: @escaping @Sendable (URL, UUID) async -> Data? = {
            pageURL,
            profileID in
            await BrowserFaviconFallbackLoader.shared.data(
                for: pageURL,
                profileID: profileID
            )
        }
    ) async -> CGImage? {
        let payloadIdentity = request.payload != nil ? request.identity.payload : nil
        var data = request.payload
        if data == nil,
            let pageURL = request.fallbackPageURL,
            let profileID = request.fallbackProfileID
        {
            data = await fallbackData(pageURL, profileID)
        }
        guard !Task.isCancelled, let data else { return nil }
        let image = await BrowserFaviconImageDecoder.decode(
            data,
            payloadIdentity: payloadIdentity,
            maximumPixelSize: request.identity.maximumPixelSize
        )
        guard !Task.isCancelled else { return nil }
        return image
    }
}
