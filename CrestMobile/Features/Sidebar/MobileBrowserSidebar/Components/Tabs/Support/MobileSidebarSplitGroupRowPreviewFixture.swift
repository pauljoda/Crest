import SwiftUI

/// Fixed identities, dates, and an in-memory store for the split-group row
/// previews, so every rendering is byte-identical between runs.
@MainActor
enum MobileSidebarSplitGroupRowPreviewFixture {
    static let spaceID = SpaceID(rawValue: uuid(0x61))
    static let profileID = uuid(0x62)
    static let groupID = SplitGroupID(rawValue: uuid(0x63))
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    static let members: [BrowserTab] = [
        tab(idByte: 0x64, title: "Design Brief", symbol: "doc.richtext"),
        tab(idByte: 0x65, title: "Reference Board", symbol: "square.grid.2x2"),
        tab(idByte: 0x66, title: "Release Notes", symbol: "note.text"),
    ]

    static func configuration(
        canClose: Bool = true,
        selectedIndex: Int? = 1
    ) -> MobileSidebarSplitGroupRowConfiguration {
        let selectedTabID = selectedIndex.map { members[$0].id }
        let space = BrowserSpace(
            id: spaceID,
            profile: BrowsingProfile(id: profileID),
            name: "Preview",
            symbol: "rectangle.split.2x1",
            accent: .indigo,
            branding: .initial(accent: .indigo, symbol: "rectangle.split.2x1"),
            folders: [],
            tabs: members,
            selectedTabID: selectedTabID
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [space],
                selectedSpaceID: spaceID
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
        return MobileSidebarSplitGroupRowConfiguration(
            groupID: groupID,
            members: members,
            spaceID: spaceID,
            profileID: profileID,
            selectedTabID: selectedTabID,
            canClose: canClose,
            browser: browser,
            spaceAccess: BrowserSpaceAccessController(
                authenticator: MobileBrowserPreviewAuthenticator()
            ),
            isLoaded: { _ in true },
            promotionNamespace: nil,
            usesNativeNavigationTransition: false,
            select: { _ in }
        )
    }

    private static func tab(
        idByte: UInt8,
        title: String,
        symbol: String
    ) -> BrowserTab {
        BrowserTab(
            id: TabID(rawValue: uuid(idByte)),
            title: title,
            url: URL(fileURLWithPath: "/preview/split/\(idByte)"),
            symbol: symbol,
            placement: .current,
            splitGroupID: groupID,
            lastActivatedAt: fixedDate
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x4D,
                0x53, 0x50,
                0x4C, 0x54,
                0x52, 0x4F, 0x57, 0x50, 0x56, finalByte
            ))
    }
}
