import AppKit
import SwiftUI

@MainActor
enum BrowserPlatformSpaceSymbolArtworkRenderer {
    static func image<Content: View>(
        for content: Content,
        size: CGFloat,
        scale: CGFloat,
        fallbackSystemImage: String
    ) -> Image {
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: size, height: size)
        renderer.scale = scale

        guard let image = renderer.nsImage?.copy() as? NSImage else {
            return Image(systemName: fallbackSystemImage)
        }
        image.isTemplate = false
        return Image(nsImage: image)
    }
}
