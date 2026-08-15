struct BrowserSourceImportPreviewSections {
    let pinnedTabs: [BrowserTab]
    let savedTabs: [BrowserTab]
    let currentTabs: [BrowserTab]
    let savedTabsByFolderID: [FolderID: [BrowserTab]]
    let unfiledSavedTabs: [BrowserTab]

    init(review: BrowserImportSpaceReview) {
        var pinnedTabs: [BrowserTab] = []
        var savedTabs: [BrowserTab] = []
        var currentTabs: [BrowserTab] = []
        var savedTabsByFolderID: [FolderID: [BrowserTab]] = [:]
        var unfiledSavedTabs: [BrowserTab] = []

        for tab in review.sourceSpace.tabs {
            switch review.placement(for: tab) {
            case .pinned:
                pinnedTabs.append(tab)
            case .saved:
                savedTabs.append(tab)
                if let folderID = tab.folderID {
                    savedTabsByFolderID[folderID, default: []].append(tab)
                } else {
                    unfiledSavedTabs.append(tab)
                }
            case .current:
                currentTabs.append(tab)
            }
        }

        self.pinnedTabs = pinnedTabs
        self.savedTabs = savedTabs
        self.currentTabs = currentTabs
        self.savedTabsByFolderID = savedTabsByFolderID
        self.unfiledSavedTabs = unfiledSavedTabs
    }
}
