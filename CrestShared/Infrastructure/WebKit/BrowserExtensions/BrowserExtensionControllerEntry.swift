import Foundation
import WebKit

struct BrowserExtensionControllerEntry {
    let controller: WKWebExtensionController
    let window: BrowserExtensionWindowAdapter
}
