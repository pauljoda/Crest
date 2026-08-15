enum ArchiveLimits {
    static let maximumFoldersPerSpace = BrowserSpace.maximumFolderCount
    static let maximumLiveTabsPerSpace = 5_000
    static let maximumArchivedTabsPerSpace = 5_000
    static let maximumHistoryEntriesPerSpace = BrowserSession.maximumHistoryEntriesPerSpace
    static let maximumSpaceNameLength = 200
    static let maximumFolderTitleLength = 500
    static let maximumTabTitleLength = 4_096
    static let maximumSymbolLength = 128
    static let maximumURLLength = 8_192
    static let maximumVisitCount = 1_000_000_000
}
