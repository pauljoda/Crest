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
            let placement = review.placement(for: tab)
            if !placement.isDurable {
                currentTabs.append(tab)
            } else if !placement.holdsFolders {
                pinnedTabs.append(tab)
            } else {
                savedTabs.append(tab)
                if let folderID = tab.folderID {
                    savedTabsByFolderID[folderID, default: []].append(tab)
                } else {
                    unfiledSavedTabs.append(tab)
                }
            }
        }

        self.pinnedTabs = pinnedTabs
        self.savedTabs = savedTabs
        self.currentTabs = currentTabs
        self.savedTabsByFolderID = savedTabsByFolderID
        self.unfiledSavedTabs = unfiledSavedTabs
    }
}
