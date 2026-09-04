import Foundation

/// How a tab announces the extension side panel bound to it.
///
/// A sidebar row can let the mark speak for itself, because the row is an
/// accessibility container and the mark stands beside the row's own label. A
/// pinned tile is one button whose label and value are written by the grid, so
/// nothing drawn inside it is ever read: the tile's value has to carry the
/// panel, and that composition lives here rather than being spelled out at the
/// call site.
enum BrowserTabSidePanelAccessibility {
    /// The label the mark itself carries, and the prefix a tile's value uses.
    static var title: String { String(localized: "Side Panel") }

    /// A tile's value, with the panel appended to whatever the tile already
    /// says about itself. `panelTitle` is written by the extension, so it is
    /// interpolated as-is and never looked up.
    static func value(_ value: String, panelTitle: String?) -> String {
        guard let panelTitle else { return value }
        return "\(value), \(title): \(panelTitle)"
    }
}
