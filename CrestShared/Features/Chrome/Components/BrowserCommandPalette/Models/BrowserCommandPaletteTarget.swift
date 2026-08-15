import Foundation

enum BrowserCommandPaletteTarget: Equatable, Hashable, Sendable {
    case tab(BrowserTabRuntimeAssignment)
    case spaceTab(BrowserTabRuntimeAssignment)
    case url(URL)
    case command(BrowserShortcutCommand)
    /// A row offered by a registered omnibox keyword provider.
    case omniboxSuggestion(BrowserOmniboxAcceptance)
}
