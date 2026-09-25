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
    let id: BrowserSidebarReorderItemID
    let tabs: [TabStateModel]
    let frame: CGRect
    var folder: FolderStateModel? = nil
    var folderRows: [BrowserFolderDragPreviewRow] = []
    var isSplit: Bool {
        if case .splitGroup = id { return true }
        return false
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.frame == rhs.frame && lhs.tabs.elementsEqual(rhs.tabs, by: ===)
            && lhs.folder === rhs.folder && lhs.folderRows.map(\.id) == rhs.folderRows.map(\.id)
    }

    @MainActor
    static func resolve(
        _ rows: [BrowserSidebarReorderRow], in space: SpaceModel,
        folderRows: (FolderID) -> [BrowserSidebarReorderRow]
    ) -> [Self] {
        rows.compactMap { row in
            let tabs: [TabStateModel]
            switch row.id {
            case .tab(let id): tabs = space.tabs.model(id).map { [$0] } ?? []
            case .splitGroup(let id): tabs = space.splitMembers(of: id)
            case .folder(let id):
                guard let folder = space.folders.model(id) else { return nil }
                return Self(
                    id: row.id, tabs: [], frame: row.frame, folder: folder,
                    folderRows: BrowserFolderDragPreviewRow.resolve(folderRows(id), in: space, rootFolderID: id))
            }
            guard !tabs.isEmpty else { return nil }
            return Self(id: row.id, tabs: tabs, frame: row.frame)
        }
    }
}
