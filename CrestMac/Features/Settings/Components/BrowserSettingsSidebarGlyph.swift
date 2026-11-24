import SwiftUI

/// A destination's glyph in the Settings sidebar, in its own color, or white
/// on the accent the list fills the selected row with while it has focus, as
/// the row's title turns, so the glyph never sinks into the selection.
struct BrowserSettingsSidebarGlyph: View {
    // MARK: - Variables

    let destination: BrowserSettingsDestination

    @Environment(\.backgroundProminence) private var prominence

    // MARK: - Actions - Drawing

    /// Semibold, so the few glyphs with no filled form, such as Search's and
    /// Links', hold their own beside the filled ones.
    var body: some View {
        Image(systemName: destination.symbol)
            .fontWeight(.semibold)
            .foregroundStyle(
                prominence == .increased ? AnyShapeStyle(Color.white) : AnyShapeStyle(destination.sidebarTint))
    }
}
