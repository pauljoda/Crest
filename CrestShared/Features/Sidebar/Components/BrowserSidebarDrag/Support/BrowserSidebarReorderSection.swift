import Foundation

/// An ordered run of sidebar rows that a lifted item can be inserted into.
///
/// Folders and tabs are separate sections even where they render in the same
/// visual column, because a folder reorders among its siblings while a tab
/// reorders among the tabs of a placement.
struct BrowserSidebarReorderSection: Hashable, Sendable {
    // MARK: - Types

    private enum Identity: Hashable, Sendable {
        case tabs(placement: TabPlacement, folderID: UUID?)
        case folders(parentID: UUID?)
    }

    // MARK: - Variables

    private let identity: Identity
    /// The tab placement when this run holds tabs, or nil for a run of folders.
    let tabPlacement: TabPlacement?
    /// The folder whose inside this run is, or nil for a run at the top level.
    let parentFolderID: UUID?
    /// A section of tabs that lays out as a grid orders on both axes.
    let usesGridOrdering: Bool
    /// The shape a lifted tab takes resting in this run: a pinned tile in the
    /// grid, a row in a list, or none for a run of folders.
    let restingPreviewShape: BrowserTabDragPreviewShape?
    private let resolveTargetList: @Sendable (DropTargetList) -> ListDropTarget?
    private let resolveOffered: @Sendable (DropTargetList) -> Bool
    private let resolveSpaceList: @MainActor @Sendable (SpaceModel) -> (placement: TabPlacement, folderID: UUID?)

    /// Whether this run orders tabs rather than folders.
    var isTabs: Bool { tabPlacement != nil }

    /// How deeply this run is nested inside the sidebar's own runs.
    ///
    /// A folder's rows are a run inside the run of the placement that holds the
    /// folder, and the two can measure the very same rectangle: a saved list
    /// whose only content is one folder group *is* that folder group, because a
    /// `VStack` around a single child takes the child's frame. Nesting is
    /// structural rather than a matter of pixels, so it is what decides which of
    /// two overlapping runs owns a pointer.
    var nestingDepth: Int { parentFolderID == nil ? 0 : 1 }

    /// Grids insert between columns, so their drop indicator is vertical.
    var flowsHorizontally: Bool { usesGridOrdering }

    // MARK: - Actions - Factories

    static func tabs(placement: TabPlacement, folderID: UUID?) -> Self {
        Self(
            identity: .tabs(placement: placement, folderID: folderID),
            tabPlacement: placement,
            parentFolderID: folderID,
            usesGridOrdering: placement.isGrid,
            restingPreviewShape: .resting(for: placement),
            resolveTargetList: { targets in
                targets.lists.first { $0.section == placement && $0.folderID == folderID }
            },
            resolveOffered: { targets in
                targets.lists.contains { $0.section == placement && $0.folderID == folderID }
            },
            resolveSpaceList: { _ in (placement, folderID) }
        )
    }

    static func folders(parentID: UUID?) -> Self {
        Self(
            identity: .folders(parentID: parentID),
            tabPlacement: nil,
            parentFolderID: parentID,
            usesGridOrdering: false,
            restingPreviewShape: nil,
            resolveTargetList: { targets in
                targets.lists.first { $0.folderID == parentID && (parentID != nil || $0.section == .saved) }
            },
            resolveOffered: { targets in
                targets.lists.contains { $0.folderID == parentID }
            },
            resolveSpaceList: { space in
                (parentID.flatMap { space.folders.model($0)?.location } ?? .saved, parentID)
            }
        )
    }

    // MARK: - Actions - Targets

    /// Whether the core lists a drop into this run among `targets`, refused or not.
    func isOffered(by targets: DropTargetList) -> Bool {
        resolveOffered(targets)
    }

    /// The list among the core's drop `targets` this run inserts into: the
    /// placement and folder of a run of tabs, or the inside of a run of
    /// folders' parent, which at the top level is the saved list.
    func list(in targets: DropTargetList) -> ListDropTarget? {
        resolveTargetList(targets)
    }

    /// The list of `space`'s sidebar this run is: the placement and folder of
    /// a run of tabs, or the inside of a run of folders' parent, in that
    /// folder's placement, which at the top level is the saved list.
    @MainActor
    func list(in space: SpaceModel) -> (placement: TabPlacement, folderID: UUID?) {
        resolveSpaceList(space)
    }

    // MARK: - Actions - Rows

    /// Rows belonging to this section, in their current visual order.
    func rows(from rows: [BrowserSidebarReorderRow]) -> [BrowserSidebarReorderRow] {
        rows.filter { $0.section == self }.sorted { $0.precedes($1) }
    }

    // MARK: - Actions - Equality

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
    }
}
