import SwiftUI

/// The colors a settings page is drawn on: Crest's cream canvas, ink in
/// dark, with paper raised on it.
enum BrowserSettingsCanvas {
    static var background: Color { CrestBrandTheme.canvas }

    /// A raised surface on the page, such as Crest Studio's preview column.
    static var card: Color { CrestBrandTheme.surface }
}
