struct BrowserCollapsedFolderTabVisibilityState: Equatable {
    private(set) var keptTabID: TabID?

    mutating func expansionDidChange(
        isExpanded: Bool,
        selectedTabID: TabID?,
        folderTabIDs: [TabID]
    ) {
        guard !isExpanded else {
            keptTabID = nil
            return
        }
        keptTabID = selectedTabID.flatMap { selectedTabID in
            folderTabIDs.contains(selectedTabID) ? selectedTabID : nil
        }
    }

    mutating func tabDidUnload(_ tabID: TabID) {
        guard keptTabID == tabID else { return }
        keptTabID = nil
    }
}
