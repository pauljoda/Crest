import SwiftUI

/// The colors a settings page is drawn on: Crest's cream canvas with paper
/// raised on it, and in dark, near-black with charcoal raised on it, as the
/// flyouts are.
enum BrowserSettingsCanvas {
    static var background: Color { CrestBrandTheme.canvas }

    /// A raised surface on the page, such as Crest Studio's preview column.
    static var card: Color { CrestBrandTheme.flyout }
}
