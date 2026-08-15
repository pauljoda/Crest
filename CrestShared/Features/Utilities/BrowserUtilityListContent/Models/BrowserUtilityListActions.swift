struct BrowserUtilityListActions {
    var restoreArchivedTab: (TabID, BrowserSpaceRuntimeAssignment) -> Void = { _, _ in }
    var openHistoryEntry: (BrowserHistoryEntry, BrowserSpaceRuntimeAssignment) -> Void = { _, _ in }
    var downloadDestinations: [BrowserUtilityDownloadDestination] = []
    var performDownloadAction: (BrowserUtilityDownloadAction, BrowserSpaceRuntimeAssignment) -> Void = { _, _ in }
}
