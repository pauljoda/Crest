import CoreGraphics
import Foundation

/// The real thing a floating lift is showing, resolved out of the Space.
///
/// The drag carries identifiers; a preview shows titles and favicons. Resolving
/// once, where the Space is already in hand, keeps the preview window a
/// presentation of the drag rather than a second place that has to look things
/// up — and keeps the three kinds of lift the sidebar can start from turning
/// into three kinds of art without anything downstream branching on drag state.
enum BrowserSidebarLiftPreviewSubject: Equatable {
    case tab(BrowserTab)
    case folder(BrowserFolder, rows: [BrowserFolderDragPreviewRow])
    /// A whole split group, in member order.
    case splitGroup([BrowserTab])
    case selection([BrowserSidebarSelectionPreviewRow])
}

struct BrowserSidebarSelectionPreviewRow: Equatable, Identifiable {
    let id: BrowserSidebarReorderItemID
    let tabs: [BrowserTab]
    let frame: CGRect
    var folder: BrowserFolder? = nil
    var folderRows: [BrowserFolderDragPreviewRow] = []
    var isSplit: Bool {
        if case .splitGroup = id { return true }
        return false
    }

    static func resolve(
        _ rows: [BrowserSidebarReorderRow], in space: BrowserSpace, folderRows: (FolderID) -> [BrowserSidebarReorderRow]
    ) -> [Self] {
        rows.compactMap { row in
            let tabs: [BrowserTab]
            switch row.id {
            case .tab(let id): tabs = space.tabs.filter { $0.id == id }
            case .splitGroup(let id): tabs = space.splitGroupMembers(of: id)
            case .folder(let id):
                guard let folder = space.folders.first(where: { $0.id == id }) else { return nil }
                return Self(
                    id: row.id, tabs: [], frame: row.frame, folder: folder,
                    folderRows: BrowserFolderDragPreviewRow.resolve(folderRows(id), in: space, rootFolderID: id))
            }
            guard !tabs.isEmpty else { return nil }
            return Self(id: row.id, tabs: tabs, frame: row.frame)
        }
    }
}
