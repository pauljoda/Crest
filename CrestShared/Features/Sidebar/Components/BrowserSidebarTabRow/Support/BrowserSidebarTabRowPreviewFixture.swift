import SwiftUI

@MainActor
enum BrowserSidebarTabRowPreviewFixture {
    static let spaceID = SpaceID(rawValue: uuid(0x71))
    static let profileID = uuid(0x72)
    static let tabID = TabID(rawValue: uuid(0x73))
    static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    static func configuration(
        placement: TabPlacement = .current,
        capabilities: BrowserInteractionCapabilities =
            BrowserInteractionCapabilities(),
        isSplitGroupMember: Bool = false
    ) -> BrowserSidebarTabRowConfiguration {
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
        return BrowserSidebarTabRowConfiguration(
            tab: tab,
            spaceID: spaceID,
            profileID: profileID,
            isSelected: true,
            canClose: true,
            browser: browser,
            spaceAccess: spaceAccess,
            capabilities: capabilities,
            isLoaded: true,
            unload: { _ in },
            pullNewIcon: {},
            restoreSavedLocation: {},
            promotionNamespace: nil,
            isSplitGroupMember: isSplitGroupMember,
            isReorderSource: !isSplitGroupMember,
            followingTabID: nil,
            hasVisibleFollowingRow: false,
            select: { _ in }
        )
    }

    static func interaction(
        isHovering: Binding<Bool>,
        isDropTargeted: Binding<Bool>,
        dropTargetHeight: Binding<CGFloat>,
        isRenaming: Bool = false,
        draftTitle: Binding<String>,
        isTitleFocused: FocusState<Bool>.Binding
    ) -> BrowserSidebarTabRowInteractionContext {
        BrowserSidebarTabRowInteractionContext(
            isHovering: isHovering,
            isDropTargeted: isDropTargeted,
            dropTargetHeight: dropTargetHeight,
            isRenaming: isRenaming,
            draftTitle: draftTitle,
            isTitleFocused: isTitleFocused,
            activate: {},
            beginRenaming: {},
            commitTitle: {},
            cancelTitleEditing: {},
            dismissFromAuxiliaryClick: {}
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
