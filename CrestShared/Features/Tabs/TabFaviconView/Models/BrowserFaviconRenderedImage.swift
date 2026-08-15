import SwiftUI

struct BrowserFaviconRenderedImage {
    let requestIdentity: BrowserFaviconTaskIdentity
    let image: Image

    func image(matching identity: BrowserFaviconTaskIdentity) -> Image? {
        guard requestIdentity == identity else { return nil }
        return image
    }
}
