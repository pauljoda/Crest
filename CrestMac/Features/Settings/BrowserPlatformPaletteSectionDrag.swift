import SwiftUI

/// Lets a person drag one of the palette's sections in Settings to a new
/// place, as any ordered list in Settings on the Mac moves.
struct BrowserPlatformPaletteSectionDrag: ViewModifier {
    let source: PaletteSource
    @Binding var dragged: PaletteSource?
    /// Moves the section being dragged to where `target` stands.
    let move: (PaletteSource, PaletteSource) -> Void

    /// The section's row, dragged as any Settings row is.
    func body(content: Content) -> some View {
        content.modifier(
            BrowserSettingsRowDrag(
                item: source, name: source.name, title: source.title, dragged: $dragged, move: move))
    }
}
