import AppKit
import WebKit

@MainActor
struct BrowserExtensionToolbarCommand: Identifiable {
    let id: String
    let title: String
    let command: WKWebExtension.Command
}
