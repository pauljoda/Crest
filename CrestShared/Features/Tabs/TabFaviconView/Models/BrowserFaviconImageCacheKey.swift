struct BrowserFaviconImageCacheKey: Hashable, Sendable {
    let payload: BrowserFaviconPayloadIdentity
    let maximumPixelSize: Int
}
