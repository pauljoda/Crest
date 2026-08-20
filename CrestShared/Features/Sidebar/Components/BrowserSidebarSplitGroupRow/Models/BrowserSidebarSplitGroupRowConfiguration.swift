import SwiftUI

/// Everything a stacked split-group row is told, and the answers that follow
/// from it.
///
/// Gathered once so the container's parts stay small and the group's rules —
/// which member is focused, where a drop beside the run lands, whether the
/// Space will accept a mutation at all — live in one place rather than in each
/// of them.
@MainActor
struct BrowserSidebarSplitGroupRowConfiguration {
    let groupID: SplitGroupID
    let members: [BrowserTab]
    let spaceID: SpaceID
    let profileID: UUID
    let selectedTabID: TabID?
    let canClose: Bool
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let capabilities: BrowserInteractionCapabilities
    let isLoaded: (TabID) -> Bool
    /// The per-tab hooks an ordinary row takes, keyed by member. The group is
    /// one row to the list and several rows to a person, so the section hands
    /// it the same actions it hands a loose tab and the group routes each to
    /// the member the row stands for.
    let unload: ((TabID) -> Void)?
    let pullNewIcon: ((TabID) -> Void)?
    let restoreSavedLocation: ((TabID) -> Void)?
    let promotionNamespace: Namespace.ID?
    /// The tab following the group's *last* member, or `nil` at the end of the
    /// section. The group is one row, so its trailing drop anchor skips past
    /// every member rather than landing between two of them.
    let followingTabID: TabID?
    let hasVisibleFollowingRow: Bool
    /// What opening a member means to the host. The group decides *which*
    /// member opens; the host decides what appears when it does.
    let select: (TabID) -> Void

    var metrics: BrowserSidebarSplitGroupRowMetrics {
        BrowserSidebarInteractionPolicy.splitGroupRowMetrics(capabilities)
    }

    /// The member rows' own profile, which the container reads for the two
    /// insets it borrows rather than chooses.
    var tabRowMetrics: BrowserSidebarTabRowMetrics {
        BrowserSidebarInteractionPolicy.tabRowMetrics(capabilities)
    }

    /// The container's inset from the sidebar edge, matching the inset a
    /// free-standing tab row gives its own surface so a group lines up in the
    /// same column as the tabs above and below it.
    var rowHorizontalInset: CGFloat {
        tabRowMetrics.surfaceHorizontalInset
    }

    /// Puts the header's glyph in the same column as the member rows'
    /// favicons: a member carries this same leading inset, and both sit inside
    /// `containerPadding`.
    var headerLeadingInset: CGFloat {
        tabRowMetrics.contentLeadingInset
    }

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
    var afterDropLocation: BrowserTabDropLocation {
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
}
