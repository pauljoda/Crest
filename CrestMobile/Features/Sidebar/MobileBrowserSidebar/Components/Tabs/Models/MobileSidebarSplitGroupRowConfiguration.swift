import SwiftUI

/// Everything the mobile stacked split-group row and its lines need, gathered
/// once so the child views stay small and the group's rules live in one place.
@MainActor
struct MobileSidebarSplitGroupRowConfiguration {
    let groupID: SplitGroupID
    let members: [BrowserTab]
    let spaceID: SpaceID
    let profileID: UUID
    let selectedTabID: TabID?
    let canClose: Bool
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let isLoaded: (TabID) -> Bool
    let promotionNamespace: Namespace.ID?
    let usesNativeNavigationTransition: Bool
    let select: (TabID) -> Void

    var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: profileID)
    }

    /// Selecting any member presents the whole split, so the container reads as
    /// selected whenever the Space's selection is one of its members.
    var isPresented: Bool {
        members.contains { $0.id == selectedTabID }
    }

    /// The member the page area focuses, and the only line that takes the
    /// selection accent. `nil` while the group is not presented at all.
    var focusedMemberID: TabID? {
        isPresented ? selectedTabID : nil
    }

    func isFocused(_ member: BrowserTab) -> Bool {
        member.id == focusedMemberID
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

    /// Where a row dropped above this group lands: in front of its first member.
    var beforeDropLocation: BrowserTabDropLocation {
        BrowserTabDropLocation(
            placement: placement,
            folderID: folderID,
            beforeTabID: members.first?.id,
            destinationAssignment: assignment
        )
    }

    /// Where a row dropped below this group lands. The group is one row, so the
    /// anchor is the tab following its *last* member, never a member itself.
    func afterDropLocation(
        followingTabID: TabID?
    ) -> BrowserTabDropLocation {
        BrowserTabDropLocation(
            placement: placement,
            folderID: folderID,
            beforeTabID: followingTabID,
            destinationAssignment: assignment
        )
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

    /// Focus is selection: selecting a member presents the whole group with that
    /// member focused, so this takes the tab row's activation path unchanged —
    /// including the guard that the touch-up ending a reorder must not also open
    /// the row it just moved.
    func activate(_ member: BrowserTab) {
        guard isCurrentAndUnlocked else { return }
        guard !browser.sidebarReorderState.suppressesActivation else { return }
        select(member.id)
    }

    /// The domain's survivor rule dissolves the group once one member is left, so
    /// this is also how a split is taken apart one pane at a time.
    func close(_ member: BrowserTab) {
        guard isCurrentAndUnlocked else { return }
        browser.closeTab(member.id, matching: assignment)
    }
}
