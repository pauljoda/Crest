import AppKit
import WebKit

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
