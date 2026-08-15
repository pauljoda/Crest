import AppKit
import WebKit

@MainActor
struct BrowserExtensionToolbarAction: Identifiable {
    let id: String
    let displayName: String
    let label: String
    let badgeText: String
    let icon: NSImage?
    let isEnabled: Bool
    let isPinned: Bool
    let action: WKWebExtension.Action
    let context: WKWebExtensionContext
    let tab: BrowserExtensionTabAdapter?
    let commands: [BrowserExtensionToolbarCommand]
    let menuItems: [BrowserExtensionToolbarMenuItem]
}
