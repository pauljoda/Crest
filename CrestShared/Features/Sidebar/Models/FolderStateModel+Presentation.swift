import Foundation

/// What the folder surfaces draw from a folder of the read model, in their
/// own vocabulary. Each member reads only the fields it names.
extension FolderStateModel {
    /// The title a folder row shows, which stands in for a folder with none.
    var shownTitle: String {
        title.isEmpty ? String(localized: "Folder") : title
    }

    /// Whether closing the folder keeps its loaded tabs on screen under its
    /// header. A group's tabs are open tabs and nearly always loaded, so a
    /// group closes to its header and the tab the window shows.
    var keepsLoadedTabsWhenClosed: Bool { !isGroup }
}
