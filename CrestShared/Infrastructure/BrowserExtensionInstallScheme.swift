import Foundation

/// The private URL scheme every in-page "Add to Crest" control navigates to.
///
/// Store bridges cannot call into Crest directly, so they mount an anchor whose
/// href uses this scheme and let the navigation delegate intercept it. The
/// scheme is shared so a new store cannot quietly introduce a second entry
/// point that the delegate does not already guard.
enum BrowserExtensionInstallScheme {
    static let rawValue = "crest-extension-install"
}
