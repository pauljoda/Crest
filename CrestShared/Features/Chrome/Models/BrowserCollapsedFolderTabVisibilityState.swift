import Foundation

/// The tabs a collapsed folder keeps on screen under its header.
///
/// Closing a folder keeps every tab it holds that is loaded then, and the one
/// the window shows. While it stays closed, a tab of it the window shows or
/// that loads joins them, so a person moving between a closed folder's tabs
/// keeps them at hand, and a tab that closes or unloads leaves at once unless
/// the window still shows it: a closed folder shows only what is loaded.
/// Opening the folder lets them all go, for the next close to keep what is
/// loaded then. A tab the folder no longer holds is read past rather than
/// removed.
struct BrowserCollapsedFolderTabVisibilityState: Equatable {
    private(set) var keptTabIDs: Set<UUID> = []
    /// Whether the person opened this folder while a closed folder around it
    /// draws it only as the way to the tabs it keeps. It then shows everything
    /// it holds, until a folder around it opens.
    private(set) var isOpenInClosedFolder = false

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

    /// Opens or closes the folder inside a closed folder around it.
    mutating func openInClosedFolder(_ isOpen: Bool) {
        isOpenInClosedFolder = isOpen
    }

    /// Forgets the folder was opened inside a closed one, once no closed
    /// folder around it draws it as the way to its tabs.
    mutating func closedFolderAroundOpened() {
        isOpenInClosedFolder = false
    }

    /// Keeps the folder's newly loaded tabs, `residentFolderTabIDs`, and lets
    /// go of every kept tab outside `loadedFolderTabIDs` but the one the
    /// window shows.
    mutating func residencyDidChange(
        isExpanded: Bool,
        selectedTabID: UUID?,
        residentFolderTabIDs: [UUID],
        loadedFolderTabIDs: [UUID]
    ) {
        guard !isExpanded else { return }
        let loaded = Set(loadedFolderTabIDs)
        keptTabIDs.formUnion(residentFolderTabIDs)
        keptTabIDs = keptTabIDs.filter { loaded.contains($0) || $0 == selectedTabID }
    }
}
