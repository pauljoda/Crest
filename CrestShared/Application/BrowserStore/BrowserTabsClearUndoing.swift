import Foundation

// MARK: - Types

/// A clear of a Space's open tabs that the core made from a window and
/// remembers as `id`: the Space it cleared, and whether the tab the window
/// showed there stayed.
struct BrowserTabsClearing: Equatable {
    let id: UUID
    let space: BrowserSpaceRuntimeAssignment
    let keepsShownTab: Bool

    /// The command the clear ran, whose title names it in Undo and Redo.
    var command: ShortcutCommand { keepsShownTab ? .clearOtherTabs : .clearAllTabs }
}

/// The window's own Undo for clearing a Space's open tabs, which takes a
/// clear back through the core. A window without one leaves the cleared
/// tabs in the Archive.
@MainActor
protocol BrowserTabsClearUndoing: AnyObject {
    /// Offers to take back `clearing`, which the core just made from this
    /// window.
    func offerUndo(of clearing: BrowserTabsClearing)
}
