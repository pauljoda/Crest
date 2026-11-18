import Foundation

/// Native actions supplied by the platform shell to a Space header.
struct BrowserSpaceHeaderActions {
    /// Opens a new tab in this Space.
    let openNewTab: () -> Void

    /// Opens another window on the same session. Gated a second time at the
    /// menu on `\.supportsMultipleWindows`, because a scene can be configured
    /// for a single window even where the shell knows how to open more.
    var openNewWindow: (() -> Void)?

    /// Creates a folder in this Space's saved tabs.
    let createFolder: () -> Void

    /// Collapses every open folder in this Space, however deep. Nil where the
    /// shell offers it elsewhere.
    var collapseAllFolders: (() -> Void)?

    /// Whether the Space has a folder open to collapse, asked as the menu
    /// opens.
    var canCollapseAllFolders: () -> Bool = { true }

    /// Opens the history list.
    let showHistory: () -> Void

    /// Opens saved passwords. Nil where the shell reaches them elsewhere.
    /// Where it is present and private browsing is on, the item becomes the
    /// disabled note that says why.
    var showPasswords: (() -> Void)?

    /// Closes every private tab. Rendered only while private browsing is on,
    /// since it is the one action that has nothing to act on otherwise.
    var closePrivateBrowsing: (() -> Void)?

    /// Opens settings. Nil where the shell has its own settings entry point.
    var showSettings: (() -> Void)?

    /// Archives the Space's open tabs but the one the window shows, leaving
    /// the pinned and saved ones alone.
    let clearOtherTabs: () -> Void

    /// Archives every open tab of the Space, the shown one too.
    let clearAllTabs: () -> Void

    /// Toggles live expansion when the header renders a retained page value.
    var toggleSavedTabs: (() -> Void)?
}
