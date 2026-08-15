import Foundation

@MainActor
enum BrowserImportPreviewFixture {
    static let previewDate = Date(timeIntervalSince1970: 1_700_000_000)
    static let folder = SavedFolder(
        id: FolderID(rawValue: uuid(3)),
        title: "Reference",
        symbol: "folder.fill"
    )
    static let pinnedTab = BrowserTab(
        id: TabID(rawValue: uuid(4)),
        title: "Design System",
        url: URL(string: "https://example.com/design"),
        symbol: "paintpalette.fill",
        placement: .pinned,
        lastActivatedAt: previewDate
    )
    static let savedTab = BrowserTab(
        id: TabID(rawValue: uuid(5)),
        title: "Project Notes",
        url: URL(string: "https://example.com/notes"),
        symbol: "note.text",
        placement: .saved,
        folderID: folder.id,
        lastActivatedAt: previewDate
    )
    static let currentTab = BrowserTab(
        id: TabID(rawValue: uuid(6)),
        title: "Dashboard",
        url: URL(string: "https://example.com/dashboard"),
        symbol: "rectangle.grid.2x2.fill",
        placement: .current,
        lastActivatedAt: previewDate
    )
    static let sourceSpace = BrowserSpace(
        id: SpaceID(rawValue: uuid(1)),
        profile: BrowsingProfile(id: uuid(2)),
        name: "Imported Work",
        symbol: "shippingbox.fill",
        accent: .orange,
        branding: .initial(accent: .orange, symbol: "shippingbox.fill"),
        folders: [folder],
        tabs: [pinnedTab, savedTab, currentTab],
        selectedTabID: currentTab.id
    )
    static let review = BrowserImportSpaceReview(
        sourceSpace: sourceSpace,
        destination: .newSpace,
        customization: BrowserImportSpaceCustomization(space: sourceSpace),
        includedTabIDs: Set(sourceSpace.tabs.map(\.id)),
        duplicateTabIDs: [],
        placementOverrides: [:],
        spaceInclusionOverride: nil,
        passwordInclusionOverride: nil
    )
    static let plan = BrowserImportReviewPlan(
        imported: BrowserPortableImport(
            spaces: [sourceSpace],
            summary: BrowserPortableImportSummary(
                spaceCount: 1,
                folderCount: sourceSpace.folders.count,
                liveTabCount: sourceSpace.tabs.count,
                archivedTabCount: 0,
                historyEntryCount: 0
            )
        ),
        existing: BrowserOnboardingWindowPreviewFixture.session
    )

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x4D, 0x6F, 0x3A, 0xA1, 0x78, 0xE4, 0x43, 0x12,
                0xA7, 0x52, 0x91, 0xC8, 0x2B, 0x10, 0x20, finalByte
            )
        )
    }
}
