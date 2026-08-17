import SwiftUI

@MainActor
enum SidebarTabRowPreviewFixture {
    static let spaceID = SpaceID(rawValue: uuid(0x71))
    static let profileID = uuid(0x72)
    static let tabID = TabID(rawValue: uuid(0x73))
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func configuration(
        placement: TabPlacement = .current,
        isSplitGroupMember: Bool = false
    ) -> SidebarTabRowConfiguration {
        let tab = BrowserTab(
            id: tabID,
            title: "Example",
            url: URL(fileURLWithPath: "/preview/example"),
            symbol: "globe",
            placement: placement,
            lastActivatedAt: fixedDate
        )
        let space = BrowserSpace(
            id: spaceID,
            profile: BrowsingProfile(id: profileID),
            name: "Preview",
            symbol: "globe",
            accent: .teal,
            branding: .initial(accent: .teal, symbol: "globe"),
            folders: [],
            tabs: [tab],
            selectedTabID: tabID
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [space],
                selectedSpaceID: spaceID
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
        let spaceAccess = BrowserSpaceAccessController(
            authenticator: BrowserPreviewAuthenticator(result: true)
        )
        return SidebarTabRowConfiguration(
            tab: tab,
            spaceID: spaceID,
            profileID: profileID,
            isSelected: true,
            canClose: true,
            browser: browser,
            spaceAccess: spaceAccess,
            presentSelectedPage: {},
            isLoaded: true,
            unload: { _ in },
            pullNewIcon: {},
            restoreSavedLocation: {},
            promotionNamespace: nil,
            isSplitGroupMember: isSplitGroupMember
        )
    }

    static func interaction(
        isHovering: Binding<Bool>,
        isDropTargeted: Binding<Bool>,
        isRenaming: Bool = false,
        draftTitle: Binding<String>,
        isTitleFocused: FocusState<Bool>.Binding
    ) -> SidebarTabRowInteractionContext {
        SidebarTabRowInteractionContext(
            isHovering: isHovering,
            isDropTargeted: isDropTargeted,
            isRenaming: isRenaming,
            draftTitle: draftTitle,
            isTitleFocused: isTitleFocused,
            beginRenaming: {},
            commitTitle: {},
            cancelTitleEditing: {},
            dismissFromMiddleClick: {}
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x54,
                0x41, 0x42,
                0x52, 0x4F,
                0x57, 0x50, 0x52, 0x45, 0x56, finalByte
            ))
    }
}
