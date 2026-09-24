import Foundation

/// A tab or folder a window's sidebar can select.
enum BrowserSelectionItemID: Codable, Hashable, Sendable {
    case tab(TabID)
    case folder(FolderID)

    var tabID: TabID? {
        if case .tab(let id) = self { return id }
        return nil
    }
    var folderID: FolderID? {
        if case .folder(let id) = self { return id }
        return nil
    }
}
