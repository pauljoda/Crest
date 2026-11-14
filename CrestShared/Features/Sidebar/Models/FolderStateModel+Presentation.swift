import SwiftUI

/// What the folder surfaces draw from a folder of the read model, in their
/// own vocabulary. Each member reads only the fields it names.
extension FolderStateModel {
    /// The title a folder row shows, which stands in for a folder with none.
    var shownTitle: String {
        title.isEmpty ? String(localized: "Folder") : title
    }

    /// What the folder is, a folder or a group, which decides what the sidebar
    /// draws and does differently for it.
    var kind: BrowserFolderKind { isGroup ? .group : .folder }
}
