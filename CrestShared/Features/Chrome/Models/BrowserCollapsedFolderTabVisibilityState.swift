import Foundation

/// The tabs a collapsed folder keeps on screen under its header.
///
/// Closing a folder keeps every tab it holds that is loaded then, and the one
/// the window shows. While it stays closed, a tab of it the window shows or
/// that loads joins them, and none leaves for unloading, so a person moving
/// between a closed folder's tabs keeps them all at hand. Only opening the
/// folder lets them go, for the next close to keep what is loaded then. A tab
/// the folder no longer holds is read past rather than removed.
struct BrowserCollapsedFolderTabVisibilityState: Equatable {
    private(set) var keptTabIDs: Set<UUID> = []

    mutating func expansionDidChange(
        isExpanded: Bool,
        selectedTabID: UUID?,
        folderTabIDs: [UUID],
        residentFolderTabIDs: [UUID]
    ) {
        guard !isExpanded else {
            keptTabIDs = []
            return
        }
        var kept = Set(residentFolderTabIDs)
        if let selectedTabID, folderTabIDs.contains(selectedTabID) { kept.insert(selectedTabID) }
        keptTabIDs = kept
    }

    mutating func selectionDidChange(
        isExpanded: Bool,
        selectedTabID: UUID?,
        folderTabIDs: [UUID]
    ) {
        guard !isExpanded,
            let selectedTabID,
            folderTabIDs.contains(selectedTabID)
        else { return }
        keptTabIDs.insert(selectedTabID)
    }

    mutating func residencyDidChange(
        isExpanded: Bool,
        residentFolderTabIDs: [UUID]
    ) {
        guard !isExpanded else { return }
        keptTabIDs.formUnion(residentFolderTabIDs)
    }
}
