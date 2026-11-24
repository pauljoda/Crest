import SwiftUI

/// An engine's logo beside its name in an Opens in menu, the artwork the
/// platform's Settings shows, or an empty slot the same size for an engine
/// without one, so every name starts at the same edge.
///
/// A native menu flattens its items to images and text, so the logo arrives
/// already drawn, in its own colours, for the menu's appearance and scale.
struct BrowserSiteEngineMenuIcon: View {
    // MARK: - Static Variables

    /// The slot every engine's icon fills, the width of a menu's symbols.
    private static let side: CGFloat = 16

    /// The logo inside that slot, inset like a symbol's glyph.
    private static let logoSize: CGFloat = 14

    /// Every drawing made so far, kept for good. The menu knows an image by
    /// its identity, so a drawing freed and drawn again can show as the one
    /// that last held its place, such as WebKit's logo beside Chromium. There
    /// are only a few: one per engine, appearance and scale.
    private static var drawings: [Drawing: Image] = [:]

    // MARK: - Types

    /// One drawing of an engine's logo, or of the empty slot.
    private struct Drawing: Hashable {
        let logo: String?
        let colorScheme: ColorScheme
        let scale: CGFloat
    }

    // MARK: - Variables

    /// The name of the logo's image in the app's assets, or nil for none.
    let logo: String?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let image = image(of: Drawing(logo: logo, colorScheme: colorScheme, scale: displayScale)) {
            image.renderingMode(.original)
        }
    }

    // MARK: - Actions - Drawing

    private func image(of drawing: Drawing) -> Image? {
        if let image = Self.drawings[drawing] { return image }
        let renderer = ImageRenderer(content: Self.artwork(of: drawing))
        renderer.scale = drawing.scale
        guard let image = renderer.cgImage.map({ Image(decorative: $0, scale: drawing.scale) }) else { return nil }
        Self.drawings[drawing] = image
        return image
    }

    private static func artwork(of drawing: Drawing) -> some View {
        ZStack {
            if let logo = drawing.logo {
                Image(logo).resizable().scaledToFit().frame(width: logoSize, height: logoSize)
            }
        }
        .frame(width: side, height: side)
        .environment(\.colorScheme, drawing.colorScheme)
    }
}
