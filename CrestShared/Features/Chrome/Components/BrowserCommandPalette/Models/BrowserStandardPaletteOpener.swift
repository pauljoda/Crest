import Foundation

/// Shared command-palette URL opener used by both macOS and mobile window root
/// models. Handles in-place and new-tab opening once, while optional closures
/// supply platform-specific Split View and Quick Window actions.
@MainActor
struct BrowserStandardPaletteOpener: BrowserCommandPaletteOpener {
    // MARK: - Variables

    let browser: BrowserStore
    let mode: BrowserCommandPaletteMode
    let loadInShownPage: @MainActor (URL) -> Void
    var openSplit: (@MainActor (URL, BrowserTabRuntimeAssignment) -> Bool)? = nil
    var openQuickWindow: (@MainActor (URL, BrowserTabRuntimeAssignment) -> Bool)? = nil

    // MARK: - Actions - Opening

    func openHere(_ url: URL, from source: BrowserTabRuntimeAssignment) -> Bool {
        if mode == .newTab { return openTab(url, from: source, selecting: true) }
        browser.navigateSelectedTab(to: url.absoluteString)
        loadInShownPage(url)
        return true
    }

    func openTab(_ url: URL, from source: BrowserTabRuntimeAssignment, selecting: Bool) -> Bool {
        guard selecting else {
            return browser.openBackgroundTab(url: url, in: source.spaceID, savesInSavedFolder: true) != nil
        }
        guard browser.openAddress(url, in: source.spaceID, placesAsNewTab: true) else { return false }
        loadInShownPage(url)
        return true
    }

    func openInSplit(_ url: URL, from source: BrowserTabRuntimeAssignment) -> Bool {
        openSplit?(url, source) ?? false
    }

    func openInQuickWindow(_ url: URL, from source: BrowserTabRuntimeAssignment) -> Bool {
        openQuickWindow?(url, source) ?? false
    }
}
