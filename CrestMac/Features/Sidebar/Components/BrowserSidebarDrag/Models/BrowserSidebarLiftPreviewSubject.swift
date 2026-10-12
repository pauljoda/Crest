import CoreGraphics
import Foundation

/// The real thing a floating lift is showing, resolved out of the Space.
///
/// The drag carries identifiers; a preview shows titles and favicons. Resolving
/// once, where the Space is already in hand, keeps the preview window a
/// presentation of the drag rather than a second place that has to look things
/// up — and keeps the three kinds of lift the sidebar can start from turning
/// into three kinds of art without anything downstream branching on drag state.
/// The objects are the read model's, so the art redraws as they change.
enum BrowserSidebarLiftPreviewSubject: Equatable {
    case tab(TabStateModel)
    case folder(FolderStateModel, rows: [BrowserFolderDragPreviewRow])
    /// A whole split group, in member order.
    case splitGroup([TabStateModel])
    case selection([BrowserSidebarSelectionPreviewRow])

    // MARK: - Actions - Layout

    /// The size the subject's art is laid out at for `lift`, before any
    /// scaling: a tab takes the shape it is morphing into, and every other
    /// subject the width of a folder row and the height of its source.
    func artSize(of lift: BrowserSidebarFloatingLift, rowWidth: CGFloat, pinnedSize: CGSize) -> CGSize {
        switch self {
        case .tab:
            lift.shape.size(rowWidth: rowWidth, pinnedSize: pinnedSize)
        case .folder, .splitGroup, .selection:
            CGSize(width: BrowserFolderDragPreviewLayout.width(for: rowWidth), height: max(lift.sourceSize.height, 1))
        }
    }

    /// The point of the art that stays under the pointer: where a selection
    /// was grabbed, or the lift's anchor in any other art of `artSize`.
    func displayAnchor(of lift: BrowserSidebarFloatingLift, artSize: CGSize) -> CGSize {
        switch self {
        case .selection:
            lift.grabOffset
        case .tab, .folder, .splitGroup:
            CGSize(width: lift.anchorFraction.x * artSize.width, height: lift.anchorFraction.y * artSize.height)
        }
    }

    /// How much the art of `artSize` is scaled: a selection never, any other
    /// art to fill `landedFrame` once it lands, and by the lift's rise while
    /// it is held.
    func scale(artSize: CGSize, landedFrame: CGRect?, reduceMotion: Bool) -> CGSize {
        switch self {
        case .selection:
            return CGSize(width: 1, height: 1)
        case .tab, .folder, .splitGroup:
            if let landedFrame {
                return CGSize(
                    width: landedFrame.width / max(artSize.width, 1),
                    height: landedFrame.height / max(artSize.height, 1))
            }
            let value = BrowserVisualAccessibilityPolicy.spatialScale(
                BrowserSidebarReorderVisuals.liftScale, reduceMotion: reduceMotion)
            return CGSize(width: value, height: value)
        }
    }

    /// Where the art of `lift` is drawn once it lands in `landedFrame`: a
    /// selection keeps its grab on the lead row of its gathered stack, and
    /// any other art its anchor.
    func landedPointer(of lift: BrowserSidebarFloatingLift, in landedFrame: CGRect, pinnedSize: CGSize) -> CGPoint {
        switch self {
        case .selection(let rows):
            let leadOffset = BrowserSidebarSelectionPreviewRow.stackOffset(
                of: lift.item.id, in: rows, shape: lift.shape, pinnedSize: pinnedSize)
            return CGPoint(
                x: landedFrame.minX + lift.grabOffset.width,
                y: landedFrame.minY + leadOffset + lift.grabOffset.height)
        case .tab, .folder, .splitGroup:
            return CGPoint(
                x: landedFrame.minX + lift.anchorFraction.x * landedFrame.width,
                y: landedFrame.minY + lift.anchorFraction.y * landedFrame.height)
        }
    }

    /// The extent the preview window covers for the subject of `lift`, grown
    /// from `base`, the envelope of every shape a lifted row takes: a
    /// selection by its rows both where they were and gathered under the
    /// grab, and a split by its member lines.
    func drawingExtent(from base: CGSize, of lift: BrowserSidebarFloatingLift) -> CGSize {
        let rowSize = BrowserTabDragPreviewLayout.rowSize
        switch self {
        case .selection(let rows):
            guard let lead = rows.first(where: { $0.id == lift.item.id }) ?? rows.first else { return base }
            var (width, height) = (base.width, base.height)
            var gatheredHeight: CGFloat = 0
            for row in rows {
                let rowWidth = max(
                    BrowserTabDragPreviewLayout.resolvedRowWidth(lift.rowWidth), row.frame.width,
                    lift.pinnedTileSize.width)
                let rowHeight = max(
                    row.frame.height, rowSize.height, lift.pinnedTileSize.height,
                    row.isSplit ? CGFloat(row.tabs.count + 1) * rowSize.height : 0)
                gatheredHeight += rowHeight
                width = max(width, abs(row.frame.minX - lead.frame.minX) + rowWidth)
                height = max(height, abs(row.frame.minY - lead.frame.minY) + rowHeight)
            }
            width += abs(lift.grabOffset.width)
            height = max(height, gatheredHeight) + abs(lift.grabOffset.height)
            return CGSize(width: width, height: height)
        case .splitGroup(let tabs):
            return CGSize(width: base.width, height: max(base.height, CGFloat(tabs.count + 1) * rowSize.height))
        case .tab, .folder:
            return base
        }
    }

    // MARK: - Actions - Equality

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.tab(let tab), .tab(let other)): tab === other
        case (.folder(let folder, let rows), .folder(let other, let otherRows)):
            folder === other && rows.map(\.id) == otherRows.map(\.id) && rows.map(\.frame) == otherRows.map(\.frame)
        case (.splitGroup(let members), .splitGroup(let others)): members.elementsEqual(others, by: ===)
        case (.selection(let rows), .selection(let others)): rows == others
        default: false
        }
    }
}

struct BrowserSidebarSelectionPreviewRow: Equatable, Identifiable {
    // MARK: - Variables

    let id: BrowserSidebarReorderItemID
    let tabs: [TabStateModel]
    let frame: CGRect
    var folder: FolderStateModel? = nil
    var folderRows: [BrowserFolderDragPreviewRow] = []
    var isSplit: Bool {
        if case .splitGroup = id { return true }
        return false
    }

    // MARK: - Actions - Resolving

    @MainActor
    static func resolve(
        _ rows: [BrowserSidebarReorderRow], in space: SpaceModel,
        folderRows: (UUID) -> [BrowserSidebarReorderRow]
    ) -> [Self] {
        rows.compactMap { row in row.id.selectionPreviewRow(at: row.frame, in: space, folderRows: folderRows) }
    }

    // MARK: - Actions - Stacking

    /// How far down the gathered stack of `rows` the row `id` starts, each
    /// row before it taking its height in the stack for a lift of `shape`.
    static func stackOffset(
        of id: BrowserSidebarReorderItemID, in rows: [Self], shape: BrowserTabDragPreviewShape, pinnedSize: CGSize
    ) -> CGFloat {
        rows.prefix { $0.id != id }.reduce(0) { $0 + $1.stackHeight(shape: shape, pinnedSize: pinnedSize) }
    }

    /// The row's height in a gathered stack for a lift of `shape`: a split or
    /// folder keeps its own, and a tab takes a row's or a tile's.
    func stackHeight(shape: BrowserTabDragPreviewShape, pinnedSize: CGSize) -> CGFloat {
        if isSplit || folder != nil { return frame.height }
        return shape == .pinnedTile ? pinnedSize.height : BrowserTabDragPreviewLayout.rowSize.height
    }

    // MARK: - Actions - Equality

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.frame == rhs.frame && lhs.tabs.elementsEqual(rhs.tabs, by: ===)
            && lhs.folder === rhs.folder && lhs.folderRows.map(\.id) == rhs.folderRows.map(\.id)
    }
}

extension BrowserSidebarReorderItemID {
    /// The selection preview row this row of `space`, measured at `frame`,
    /// shows: its tab, its split's members, or its folder with the rows
    /// `folderRows` measures inside it; nil once the Space no longer holds it.
    @MainActor
    func selectionPreviewRow(
        at frame: CGRect, in space: SpaceModel, folderRows: (UUID) -> [BrowserSidebarReorderRow]
    ) -> BrowserSidebarSelectionPreviewRow? {
        let tabs: [TabStateModel]
        switch self {
        case .tab(let id): tabs = space.tabs.model(id).map { [$0] } ?? []
        case .splitGroup(let id): tabs = space.splitMembers(of: id)
        case .folder(let id):
            guard let folder = space.folders.model(id) else { return nil }
            return BrowserSidebarSelectionPreviewRow(
                id: self, tabs: [], frame: frame, folder: folder,
                folderRows: BrowserFolderDragPreviewRow.resolve(folderRows(id), in: space, rootFolderID: id))
        }
        guard !tabs.isEmpty else { return nil }
        return BrowserSidebarSelectionPreviewRow(id: self, tabs: tabs, frame: frame)
    }
}

extension BrowserSidebarReorderItem {
    /// What the floating lift of this row alone shows, resolved in `space`:
    /// the tab, the folder with `previewRows`, the rows measured inside it,
    /// or the split's members; nil once the Space no longer holds it. A run
    /// that has already lost its members has nothing to draw; the drag itself
    /// is ended by the same change.
    @MainActor
    func liftPreviewSubject(
        in space: SpaceModel, previewRows: [BrowserSidebarReorderRow]
    ) -> BrowserSidebarLiftPreviewSubject? {
        switch self {
        case .tab(let tab):
            return space.tabs.model(tab.tabID).map(BrowserSidebarLiftPreviewSubject.tab)
        case .folder(let folder):
            let rows = BrowserFolderDragPreviewRow.resolve(previewRows, in: space, rootFolderID: folder.folderID)
            return space.folders.model(folder.folderID).map { .folder($0, rows: rows) }
        case .splitGroup(let group):
            let members = space.splitMembers(of: group.groupID)
            return members.isEmpty ? nil : .splitGroup(members)
        }
    }
}
