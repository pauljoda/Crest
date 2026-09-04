import AppKit

/// The rows the side-panel switcher offers, resolved from the panels the host
/// can present right now.
///
/// The model is rebuilt for each presentation rather than cached, because the
/// set of available panels changes while the menu is closed and a stale row
/// would offer an extension that is no longer there. Keeping the resolution
/// here — title, checked row, and artwork — leaves the AppKit presenter as a
/// plain translation into `NSMenuItem`s.
struct BrowserExtensionSidebarSwitcherMenuModel {
    struct Item: Identifiable {
        let clientID: BrowserExtensionServiceClientID
        let title: String
        let icon: NSImage
        let isCurrent: Bool

        var id: BrowserExtensionServiceClientID { clientID }
    }

    /// Rows draw their artwork at the size the header shows above them.
    static let iconSize = NSSize(width: 16, height: 16)
    static let fallbackSymbolName = "puzzlepiece.extension.fill"

    let items: [Item]

    /// The header only earns a menu once a second panel could take its place.
    var presentsSwitcher: Bool { items.count > 1 }

    var currentTitle: String? { items.first(where: \.isCurrent)?.title }

    init(
        panels: [BrowserExtensionSidebarPanel],
        currentClientID: BrowserExtensionServiceClientID?,
        icon: (BrowserExtensionSidebarPanel) -> NSImage?
    ) {
        items = panels.map { panel in
            Item(
                clientID: panel.clientID,
                title: panel.title,
                icon: Self.rowIcon(icon(panel)),
                isCurrent: panel.clientID == currentClientID
            )
        }
    }

    /// An extension's own artwork keeps its colors, so the menu reads like the
    /// toolbar it stands in for. The puzzle-piece fallback stays a template
    /// image instead, so an extension that ships no icon still gets a glyph
    /// that follows the menu's label color in either appearance.
    private static func rowIcon(_ artwork: NSImage?) -> NSImage {
        guard let sized = artwork?.copy() as? NSImage else {
            let fallback = NSImage(systemSymbolName: fallbackSymbolName, accessibilityDescription: nil)
            fallback?.size = iconSize
            return fallback ?? NSImage(size: iconSize)
        }
        sized.size = iconSize
        sized.isTemplate = false
        return sized
    }
}
