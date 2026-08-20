import Foundation

/// Everything a Space header's menu can offer, as the shell's own closures.
///
/// The two shells' menus diverge by what each can actually reach rather than
/// by which one they are: only the windowed shell manages extensions from
/// here, only the compact one reaches passwords, settings, and a second
/// window. So the menu is not a fixed list with platform holes cut in it — it
/// is exactly the closures that arrived, and a shell that gains a feature gets
/// the item by passing one rather than by editing the menu.
///
/// The four that every shell has stay non-optional, because a Space header
/// without a way to open a tab or clean up is not a header anyone shipped.
struct BrowserSpaceHeaderActions {
    /// Opens a new tab in this Space.
    let openNewTab: () -> Void

    /// Opens another window on the same session. Gated a second time at the
    /// menu on `\.supportsMultipleWindows`, because a scene can be configured
    /// for a single window even where the shell knows how to open more.
    var openNewWindow: (() -> Void)?

    /// Creates a folder in this Space's saved tabs.
    let createFolder: () -> Void

    /// Opens the history list.
    let showHistory: () -> Void

    /// Opens extension management. Nil where the shell has no extension UI of
    /// its own. Where it is present and private browsing is on, the item
    /// becomes the disabled note that says why.
    var showExtensions: (() -> Void)?

    /// Opens saved passwords. Nil where the shell reaches them elsewhere.
    /// Where it is present and private browsing is on, the item becomes the
    /// disabled note that says why.
    var showPasswords: (() -> Void)?

    /// Closes every private tab. Rendered only while private browsing is on,
    /// since it is the one action that has nothing to act on otherwise.
    var closePrivateBrowsing: (() -> Void)?

    /// Opens settings. Nil where the shell has its own settings entry point.
    var showSettings: (() -> Void)?

    /// Closes the Space's current tabs, leaving the saved ones alone.
    let cleanup: () -> Void
}
