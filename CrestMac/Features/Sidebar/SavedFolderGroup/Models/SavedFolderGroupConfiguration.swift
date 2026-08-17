import Foundation

@MainActor
struct SavedFolderGroupConfiguration {
    let node: BrowserFolderNode
    let tabs: [BrowserTab]
    let spaceID: SpaceID
    let profileID: UUID
    let selectedTabID: TabID?
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController

    var folder: SavedFolder { node.folder }

    var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: profileID)
    }

    /// How far a row inside this folder is indented. Tab rows and stacked
    /// split-group rows share it so a group never breaks the nesting rhythm.
    var rowLeadingInset: CGFloat {
        14 + CGFloat(node.depth) * 14
    }

    /// The folder's rows, with contiguous split runs folded into group rows.
    var items: [BrowserSidebarTabListItem] {
        BrowserSidebarTabListItemPolicy.items(for: tabs)
    }

    var folderRuntimeAssignment: BrowserFolderRuntimeAssignment {
        BrowserFolderRuntimeAssignment(
            folderID: folder.id,
            spaceID: spaceID,
            profileID: profileID
        )
    }

    var isCurrentAndUnlocked: Bool {
        BrowserSidebarAccessPolicy.selectedUnlockedSpace(
            matching: assignment,
            in: browser,
            accessController: spaceAccess
        ) != nil
    }

    var tabDropLocation: BrowserTabDropLocation {
        BrowserTabDropLocation(
            placement: .saved,
            folderID: folder.id,
            beforeTabID: nil
        )
    }

    var folderDropLocation: BrowserFolderDropLocation {
        BrowserFolderDropLocation(
            parentID: folder.parentID,
            beforeSiblingID: folder.id
        )
    }

    var folderInsideDropLocation: BrowserFolderDropLocation {
        BrowserFolderDropLocation(
            parentID: folder.id,
            beforeSiblingID: nil
        )
    }

    var tabActions: BrowserSidebarTabActions {
        BrowserSidebarTabActions(
            assignment: BrowserSpaceRuntimeAssignment(
                spaceID: spaceID,
                profileID: profileID
            ),
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        )
    }

    func keptCollapsedTab(
        for state: BrowserCollapsedFolderTabVisibilityState
    ) -> BrowserTab? {
        guard let keptTabID = state.keptTabID,
            pages.containsResidentPage(for: keptTabID)
        else {
            return nil
        }
        return tabs.first { $0.id == keptTabID }
    }

    var residentFolderTabIDs: [TabID] {
        tabs.compactMap { tab in
            pages.containsResidentPage(for: tab.id) ? tab.id : nil
        }
    }
}
