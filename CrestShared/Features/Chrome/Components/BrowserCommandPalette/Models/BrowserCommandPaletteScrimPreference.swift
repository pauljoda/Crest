import Foundation

/// Whether the command bar dims the window behind it while it floats over
/// the page. With dimming off, a click outside the bar still closes it.
enum BrowserCommandPaletteScrimPreference {
    static let key = "crest.appearance.command-bar-dims-page"
    static let defaultValue = true
}
