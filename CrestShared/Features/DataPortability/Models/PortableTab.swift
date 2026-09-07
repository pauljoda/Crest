import Foundation

struct PortableTab: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let nativeContent: BrowserNativeTabContent?
    let url: String?
    let savedURL: String?
    let symbol: String
    let placement: TabPlacement
    let folderID: UUID?
    let splitGroupID: UUID?
    let lastActivatedAt: Date

    init(_ tab: BrowserTab) {
        id = tab.id.rawValue
        nativeContent = tab.nativeContent
        title = tab.title
        url =
            ArchiveValidation.sanitizedURL(tab.url, removesFragment: false)?
            .absoluteString
        savedURL =
            ArchiveValidation.sanitizedURL(
                tab.savedSiteURL,
                removesFragment: false
            )?.absoluteString
        symbol = tab.symbol
        placement = tab.placement
        folderID = tab.folderID?.rawValue
        splitGroupID = tab.splitGroupID?.rawValue
        lastActivatedAt = tab.lastActivatedAt
    }

    func materialize(
        folderIDsBySourceID: [UUID: FolderID],
        splitGroupIDsBySourceID: [UUID: SplitGroupID]
    ) throws -> BrowserTab {
        try ArchiveValidation.requireText(title, maximumLength: ArchiveLimits.maximumTabTitleLength)
        try ArchiveValidation.requireText(symbol, maximumLength: ArchiveLimits.maximumSymbolLength)
        try ArchiveValidation.requireDate(lastActivatedAt)
        if let nativeContent {
            try ArchiveValidation.requireText(nativeContent.kind, maximumLength: 128)
            guard url == nil, savedURL == nil else { throw BrowserPortableArchiveError.invalidContents }
        }
        let materializedURL = try ArchiveValidation.materializeURL(
            url,
            removesFragment: false
        )
        let materializedSavedURL = try ArchiveValidation.materializeURL(
            savedURL,
            removesFragment: false
        )

        let materializedFolderID: FolderID?
        if placement != .pinned, let folderID {
            guard let mappedID = folderIDsBySourceID[folderID] else {
                throw BrowserPortableArchiveError.invalidContents
            }
            materializedFolderID = mappedID
        } else {
            guard folderID == nil else {
                throw BrowserPortableArchiveError.invalidContents
            }
            materializedFolderID = nil
        }

        return BrowserTab(
            title: nativeContent == nil && materializedURL == nil ? BrowserTab.startPageTitle : title,
            url: materializedURL,
            nativeContent: nativeContent,
            savedURL: placement == .current ? nil : materializedSavedURL ?? materializedURL,
            symbol: nativeContent == nil && materializedURL == nil ? BrowserTab.startPageSymbol : symbol,
            faviconData: nil,
            placement: placement,
            folderID: materializedFolderID,
            splitGroupID: splitGroupID.flatMap {
                splitGroupIDsBySourceID[$0]
            },
            lastActivatedAt: lastActivatedAt
        )
    }
}
