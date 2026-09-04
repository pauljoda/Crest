import AppKit
import SwiftUI

struct BrowserCommandContext {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let chrome: BrowserChromeState
    let windowID: BrowserWindowID?
    var extensionSidebar: BrowserExtensionSidebarHost? = nil
}
