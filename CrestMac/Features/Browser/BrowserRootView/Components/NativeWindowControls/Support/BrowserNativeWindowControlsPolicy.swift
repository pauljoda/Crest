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
}
