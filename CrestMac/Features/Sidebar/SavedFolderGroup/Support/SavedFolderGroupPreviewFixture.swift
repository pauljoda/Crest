import SwiftUI

@MainActor
enum SavedFolderGroupPreviewFixture {
    static let folderID = FolderID(rawValue: uuid(0x81))
    static let spaceID = SpaceID(rawValue: uuid(0x82))
    static let profileID = uuid(0x83)
    static let tabID = TabID(rawValue: uuid(0x84))

    static func configuration() -> SavedFolderGroupConfiguration {
        let folder = SavedFolder(
            id: folderID,
            title: "Research",
            symbol: "folder.fill",
            color: .teal
        )
        let tab = BrowserTab(
            id: tabID,
            title: "SwiftUI Layout",
            url: URL(fileURLWithPath: "/preview/swiftui-layout"),
            symbol: "rectangle.3.group.fill",
            placement: .saved,
            folderID: folderID,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let space = BrowserSpace(
            id: spaceID,
            profile: BrowsingProfile(id: profileID),
            name: "Studio",
            symbol: "paintpalette.fill",
            accent: .teal,
            branding: .initial(accent: .teal, symbol: "paintpalette.fill"),
            folders: [folder],
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
        let pages = BrowserPagePool(
            browsingMode: .privateBrowsing,
            usesEphemeralWebsiteDataStores: true
        )
        let spaceAccess = BrowserSpaceAccessController(
            authenticator: BrowserSidebarPreviewAuthenticator()
        )
        return SavedFolderGroupConfiguration(
            node: BrowserFolderNode(
                folder: folder,
                depth: 0,
                hasChildren: false
            ),
            tabs: [tab],
            spaceID: spaceID,
            profileID: profileID,
            selectedTabID: tabID,
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        )
    }

    static func interaction(
        isExpanded: Binding<Bool>,
        editingFolderRequest: Binding<BrowserFolderRuntimeAssignment?>,
        isDropTargeted: Binding<Bool> = .constant(false),
        draftTitle: Binding<String> = .constant("Research"),
        isChoosingColor: Binding<Bool> = .constant(false),
        isConfirmingDeletion: Binding<Bool> = .constant(false),
        collapsedTabVisibility:
            Binding<BrowserCollapsedFolderTabVisibilityState>,
        isTitleFocused: FocusState<Bool>.Binding
    ) -> SavedFolderGroupInteractionContext {
        SavedFolderGroupInteractionContext(
            isExpanded: isExpanded,
            editingFolderRequest: editingFolderRequest,
            isDropTargeted: isDropTargeted,
            draftTitle: draftTitle,
            isChoosingColor: isChoosingColor,
            isConfirmingDeletion: isConfirmingDeletion,
            collapsedTabVisibility: collapsedTabVisibility,
            isTitleFocused: isTitleFocused,
            folderColor: .constant(.teal),
            beginCreatingChild: {},
            beginRenaming: {},
            toggleExpansion: {},
            beginTitleEditingIfNeeded: {},
            commitTitle: {},
            cancelTitleEditing: {},
            deleteFolder: {},
            unloadKeptCollapsedTab: { _ in }
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x46,
                0x4F, 0x4C,
                0x44, 0x45,
                0x52, 0x50, 0x52, 0x45, 0x56, finalByte
            ))
    }
}
