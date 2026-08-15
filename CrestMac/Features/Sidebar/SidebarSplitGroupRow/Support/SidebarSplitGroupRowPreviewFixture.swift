import SwiftUI

@MainActor
enum SidebarSplitGroupRowPreviewFixture {
    static let spaceID = SpaceID(rawValue: uuid(0x61))
    static let profileID = uuid(0x62)
    static let groupID = SplitGroupID(rawValue: uuid(0x63))
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    /// Titles for the pool the previews draw members from, in order. Four is
    /// `BrowserSplitGroupPolicy.maximumMembers`, so every renderable size can be
    /// taken as a prefix of one fixed list.
    private static let memberTitles = [
        ("Design Brief", "doc.richtext"),
        ("Reference Board", "square.grid.2x2"),
        ("Release Notes", "note.text"),
        ("Changelog", "list.bullet.rectangle"),
    ]

    static func members(
        count: Int = 3,
        placement: TabPlacement = .current
    ) -> [BrowserTab] {
        memberTitles.prefix(count).enumerated().map { index, member in
            tab(
                idByte: UInt8(0x64 + index),
                title: member.0,
                symbol: member.1,
                placement: placement,
                groupID: groupID
            )
        }
    }

    /// An ordinary tab in the same section, so a preview can put a group beside
    /// the rows it has to read as one of.
    static func neighborTab(placement: TabPlacement = .current) -> BrowserTab {
        tab(
            idByte: 0x70,
            title: "Weekly Notes",
            symbol: "calendar",
            placement: placement,
            groupID: nil
        )
    }

    static func configuration(
        memberCount: Int = 3,
        canClose: Bool = true,
        selectedIndex: Int? = 1,
        placement: TabPlacement = .current
    ) -> SidebarSplitGroupRowConfiguration {
        let members = members(count: memberCount, placement: placement)
        let selectedTabID = selectedIndex.map { members[$0].id }
        let space = BrowserSpace(
            id: spaceID,
            profile: BrowsingProfile(id: profileID),
            name: "Preview",
            symbol: "rectangle.split.2x1",
            accent: .indigo,
            branding: .initial(accent: .indigo, symbol: "rectangle.split.2x1"),
            folders: [],
            tabs: members + [neighborTab(placement: placement)],
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
        return SidebarSplitGroupRowConfiguration(
            groupID: groupID,
            members: members,
            spaceID: spaceID,
            profileID: profileID,
            selectedTabID: selectedTabID,
            canClose: canClose,
            browser: browser,
            spaceAccess: BrowserSpaceAccessController(
                authenticator: BrowserSidebarPreviewAuthenticator()
            ),
            presentSelectedPage: {},
            isLoaded: { _ in true },
            unload: nil,
            pullNewIcon: nil,
            restoreSavedLocation: nil
        )
    }

    /// Every combination of the given sizes and selections, so one preview can
    /// show a group at each renderable size both presented and at rest.
    static func configurations(
        memberCounts: [Int],
        selectedIndexes: [Int?],
        placement: TabPlacement = .current
    ) -> [SidebarSplitGroupRowConfiguration] {
        memberCounts.flatMap { memberCount in
            selectedIndexes.map { selectedIndex in
                configuration(
                    memberCount: memberCount,
                    canClose: placement == .current,
                    selectedIndex: selectedIndex.map {
                        min($0, memberCount - 1)
                    },
                    placement: placement
                )
            }
        }
    }

    private static func tab(
        idByte: UInt8,
        title: String,
        symbol: String,
        placement: TabPlacement,
        groupID: SplitGroupID?
    ) -> BrowserTab {
        BrowserTab(
            id: TabID(rawValue: uuid(idByte)),
            title: title,
            url: URL(fileURLWithPath: "/preview/split/\(idByte)"),
            symbol: symbol,
            placement: placement,
            splitGroupID: groupID,
            lastActivatedAt: fixedDate
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x53,
                0x50, 0x4C,
                0x49, 0x54,
                0x52, 0x4F, 0x57, 0x50, 0x56, finalByte
            ))
    }
}
