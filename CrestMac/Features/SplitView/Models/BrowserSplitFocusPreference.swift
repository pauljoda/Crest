import Foundation

/// How Split View decides which card the pointer means.
///
/// Off by default. Click-to-focus is the behaviour every browser has; focus
/// following the pointer is a choice, and one that surprises anyone who did not
/// ask for it — a mouse crossing the window on its way to the Dock would change
/// which page ⌘L, ⌘F, and the reload button speak for.
struct BrowserSplitFocusPreference: Equatable, Sendable {
    var followsMouse: Bool = false
}
