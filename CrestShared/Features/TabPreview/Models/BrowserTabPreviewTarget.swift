import Foundation

// MARK: - Types

/// One tab or folder in one Space, which tells one preview target from
/// another.
struct BrowserTabPreviewKey: Hashable {
    let item: BrowserSelectionItemID
    let spaceID: UUID
}

/// A sidebar tab or folder a preview card is for: what it is, the list that
/// draws it, and where its row or tile sits in the window.
struct BrowserTabPreviewTarget {
    // MARK: - Variables

    let subject: BrowserTabPreviewSubject
    let context: BrowserSidebarListContext
    /// The row's or tile's frame in the window, in points.
    let frame: CGRect
    /// Whether a finger held the row for this card, rather than the pointer
    /// or the keyboard resting on it. Its card shows over a scrim, above or
    /// below the row, and stays until the person dismisses it.
    var isHeldByTouch = false
    /// The folder's own menu, which a held folder's card offers behind "…".
    var folderMenu: BrowserFolderOrganizationMenu?

    /// The tab or folder in its Space.
    @MainActor var key: BrowserTabPreviewKey {
        BrowserTabPreviewKey(item: subject.item, spaceID: context.space.id)
    }
}

extension BrowserTabPreviewTarget {
    /// This target where it now sits, held as `held` was, with its menu.
    func held(from held: BrowserTabPreviewTarget) -> BrowserTabPreviewTarget {
        var target = self
        target.isHeldByTouch = held.isHeldByTouch
        target.folderMenu = held.folderMenu
        return target
    }
}
