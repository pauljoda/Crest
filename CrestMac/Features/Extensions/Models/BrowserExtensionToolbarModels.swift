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

@MainActor
struct BrowserExtensionToolbarCommand: Identifiable {
    let id: String
    let title: String
    let command: WKWebExtension.Command
}

@MainActor
struct BrowserExtensionToolbarMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let isEnabled: Bool
    let isSeparator: Bool
    let children: [BrowserExtensionToolbarMenuItem]
    let item: NSMenuItem

    init(item: NSMenuItem) {
        title = item.title
        isEnabled = item.isEnabled
        isSeparator = item.isSeparatorItem
        children = item.submenu?.items.map(Self.init(item:)) ?? []
        self.item = item
    }
}

struct BrowserExtensionCommandSummary: Equatable, Identifiable {
    let extensionID: String
    let extensionDisplayName: String
    let commandID: String
    let title: String
    let shortcut: BrowserShortcut?
    let isCustomized: Bool

    var id: String { "\(extensionID).\(commandID)" }

    func matches(search query: String) -> Bool {
        let query = query.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        guard !query.isEmpty else { return true }
        return [
            extensionDisplayName,
            title,
            commandID,
            shortcut?.displayString ?? "unassigned",
            shortcut?.spokenDescription ?? "no shortcut",
        ].joined(separator: " ").lowercased().contains(query)
    }
}
