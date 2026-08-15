import SwiftUI

@MainActor
struct SidebarSplitGroupRowConfiguration {
    let groupID: SplitGroupID
    let members: [BrowserTab]
    let spaceID: SpaceID
    let profileID: UUID
    let selectedTabID: TabID?
    let canClose: Bool
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let presentSelectedPage: () -> Void
    let isLoaded: (TabID) -> Bool
    /// The per-tab hooks an ordinary row takes, keyed by member. The group is
    /// one row to the list and several rows to a person, so the section hands
    /// it the same actions it hands a loose tab and the group routes each to
    /// the member the row stands for.
    let unload: ((TabID) -> Void)?
    let pullNewIcon: ((TabID) -> Void)?
    let restoreSavedLocation: ((TabID) -> Void)?

    var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: profileID)
    }

    /// Selecting any member presents the whole split, so the container reads as
    /// presented whenever the Space's selection is one of its members.
    var isPresented: Bool {
        members.contains { $0.id == selectedTabID }
    }

    /// The member the content area focuses, and the only row that takes the
    /// selection accent. `nil` while the group is not presented at all.
    var focusedMemberID: TabID? {
        isPresented ? selectedTabID : nil
    }

    func isFocused(_ member: BrowserTab) -> Bool {
        member.id == focusedMemberID
    }

    func pullNewIcon(for member: BrowserTab) -> (() -> Void)? {
        guard let pullNewIcon else { return nil }
        return { pullNewIcon(member.id) }
    }

    func restoreSavedLocation(for member: BrowserTab) -> (() -> Void)? {
        guard let restoreSavedLocation else { return nil }
        return { restoreSavedLocation(member.id) }
    }

    /// The run is uniform by construction — the normalizer clears any member
    /// whose placement or folder drifts from the head's — so the head answers
    /// for the whole group.
    var placement: TabPlacement {
        members.first?.placement ?? .current
    }

    var folderID: FolderID? {
        members.first?.folderID
    }

    var dragItem: BrowserSplitGroupDragItem {
        BrowserSplitGroupDragItem(
            groupID: groupID,
            spaceID: spaceID,
            profileID: profileID,
            memberTabIDs: members.map(\.id)
        )
    }

    var reorderContext: BrowserSidebarReorderContext {
        BrowserSidebarReorderContext(
            browser: browser,
            spaceAccess: spaceAccess
        )
    }

    /// Every mutation this row offers is refused unless the Space is the selected
    /// unlocked one and still holds the group.
    var isCurrentAndUnlocked: Bool {
        guard
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: assignment,
                in: browser,
                accessController: spaceAccess
            )
        else { return false }
        return space.tabs.contains { $0.splitGroupID == groupID }
    }
}
