import Foundation

extension BrowserFaviconPaletteLoader {
    /// The loader every page shares, which reads a favicon's palette off the
    /// main actor through ImageIO.
    static let shared = BrowserFaviconPaletteLoader { data in
        await Task.detached(priority: .utility) {
            BrowserFaviconPaletteExtractor().palette(imageData: data)
        }.value
    }
}
