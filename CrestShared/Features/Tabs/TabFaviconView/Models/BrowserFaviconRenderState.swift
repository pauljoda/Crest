import SwiftUI

@MainActor
struct BrowserFaviconRenderState {
    private(set) var activeRequestIdentity: BrowserFaviconTaskIdentity?
    private(set) var renderedImage: BrowserFaviconRenderedImage?

    mutating func begin(
        _ requestIdentity: BrowserFaviconTaskIdentity,
        isCancelled: Bool
    ) {
        guard !isCancelled else { return }
        activeRequestIdentity = requestIdentity
    }

    mutating func publish(
        _ image: Image,
        for requestIdentity: BrowserFaviconTaskIdentity,
        isCancelled: Bool
    ) {
        guard !isCancelled,
            activeRequestIdentity == requestIdentity
        else { return }
        renderedImage = BrowserFaviconRenderedImage(
            requestIdentity: requestIdentity,
            image: image
        )
    }
}
