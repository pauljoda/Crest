import AppKit

enum BrowserNativeWindowControlsPolicy {
    static let toolbarIdentifier = NSToolbar.Identifier(
        "crest.browser.window-chrome"
    )
    static let buttonTypes: [NSWindow.ButtonType] = [
        .closeButton,
        .miniaturizeButton,
        .zoomButton,
    ]

    static func showsToolbar(in styleMask: NSWindow.StyleMask) -> Bool {
        !styleMask.contains(.fullScreen)
    }

    /// A collapsed sidebar owns no place for window controls in ordinary
    /// windowed chrome. Native fullscreen supplies its own top bar, so those
    /// standard controls remain available there regardless of sidebar state.
    static func showsWindowControls(
        sidebarPresentationShowsControls: Bool,
        in styleMask: NSWindow.StyleMask
    ) -> Bool {
        sidebarPresentationShowsControls || styleMask.contains(.fullScreen)
    }
}
