import SwiftUI
import UIKit

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

        guard let image = renderer.uiImage else {
            return Image(systemName: fallbackSystemImage)
        }
        return Image(uiImage: image.withRenderingMode(.alwaysOriginal))
    }
}
