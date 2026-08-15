/// An ordered run of sidebar rows that a lifted item can be inserted into.
///
/// Folders and tabs are separate sections even where they render in the same
/// visual column, because a folder reorders among its siblings while a tab
/// reorders among the tabs of a placement.
enum BrowserSidebarReorderSection: Hashable, Sendable {
    case tabs(placement: TabPlacement, folderID: FolderID?)
    case folders(parentID: FolderID?)

    /// How deeply this run is nested inside the sidebar's own runs.
    ///
    /// A folder's rows are a run inside the run of the placement that holds the
    /// folder, and the two can measure the very same rectangle: a saved list
    /// whose only content is one folder group *is* that folder group, because a
    /// `VStack` around a single child takes the child's frame. Nesting is
    /// structural rather than a matter of pixels, so it is what decides which of
    /// two overlapping runs owns a pointer.
    var nestingDepth: Int {
        switch self {
        case .tabs(_, let folderID): folderID == nil ? 0 : 1
        case .folders(let parentID): parentID == nil ? 0 : 1
        }
    }

    /// Pinned tabs lay out as a grid, so ordering compares on both axes.
    var usesGridOrdering: Bool {
        switch self {
        case .tabs(let placement, _): placement == .pinned
        case .folders: false
        }
    }

    /// Grids insert between columns, so their drop indicator is vertical.
    var flowsHorizontally: Bool {
        usesGridOrdering
    }
}
