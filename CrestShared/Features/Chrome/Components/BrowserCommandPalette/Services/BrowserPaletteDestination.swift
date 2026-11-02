import Foundation

/// Where a palette with no tab of its own opens what the person picks: a
/// window's New Tab surface, or a page outside the window's tabs, such as a
/// Quick Window's. Each action checks again that the destination can act.
@MainActor
protocol BrowserPaletteDestination {
    /// The Space the destination opens into.
    var source: BrowserSpaceRuntimeAssignment { get }
    /// The Space the core's palette speaks for when the destination is a page
    /// outside the window's tabs; nil speaks for the Space the window shows.
    var paletteSpaceID: UUID? { get }
    var isAvailable: Bool { get }

    /// Shows the tab `target` names, answering whether it did.
    func selectTab(_ target: BrowserTabRuntimeAssignment) -> Bool

    /// Opens `url`, answering whether it did.
    func openURL(_ url: URL) -> Bool
}
