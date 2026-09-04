import Foundation

/// How a tab announces the extension side panel bound to it.
///
/// Neither shape of tab can let the mark speak for itself. A pinned tile is one
/// button whose label and value are written by the grid, and a sidebar row is
/// an accessibility container whose one labelled element is the activation
/// button — the badge is drawn inside both, so anything it declared would be
/// merged away. Each writes the panel into that element's value instead, and
/// the composition lives here rather than being spelled out at two call sites
/// that would drift apart.
enum BrowserTabSidePanelAccessibility {
    /// The prefix the panel is announced under.
    static var title: String { String(localized: "Side Panel") }

    /// A tab's value, with the panel appended to whatever the tab already says
    /// about itself. `panelTitle` is written by the extension, so it is
    /// interpolated as-is and never looked up.
    static func value(_ value: String, panelTitle: String?) -> String {
        guard let panelTitle else { return value }
        return "\(value), \(title): \(panelTitle)"
    }
}
