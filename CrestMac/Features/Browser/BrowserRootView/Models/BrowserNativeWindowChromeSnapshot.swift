import AppKit

struct BrowserNativeWindowChromeSnapshot {
    let styleMask: NSWindow.StyleMask
    let titlebarAppearsTransparent: Bool
    let titleVisibility: NSWindow.TitleVisibility
    let titlebarSeparatorStyle: NSTitlebarSeparatorStyle
    let toolbar: NSToolbar?
    let toolbarStyle: NSWindow.ToolbarStyle
    let contentFrameClipsToBounds: Bool
    let buttonVisibility: [(NSWindow.ButtonType, Bool)]
}
