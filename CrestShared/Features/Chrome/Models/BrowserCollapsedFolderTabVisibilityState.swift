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

    mutating func selectionDidChange(
        isExpanded: Bool,
        selectedTabID: TabID?,
        folderTabIDs: [TabID]
    ) {
        guard !isExpanded,
            let selectedTabID,
            folderTabIDs.contains(selectedTabID)
        else { return }
        keptTabID = selectedTabID
    }

    mutating func residencyDidChange(
        isExpanded: Bool,
        selectedTabID: TabID?,
        residentFolderTabIDs: [TabID]
    ) {
        if let keptTabID,
            !residentFolderTabIDs.contains(keptTabID)
        {
            self.keptTabID = nil
        }
        guard !isExpanded,
            let selectedTabID,
            residentFolderTabIDs.contains(selectedTabID)
        else { return }
        keptTabID = selectedTabID
    }

    mutating func tabDidUnload(_ tabID: TabID) {
        guard keptTabID == tabID else { return }
        keptTabID = nil
    }
}
