import SwiftUI

@MainActor
struct SidebarTabRowConfiguration {
    let tab: BrowserTab
    let spaceID: SpaceID
    let profileID: UUID
    let isSelected: Bool
    let canClose: Bool
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let presentSelectedPage: () -> Void
    let isLoaded: Bool
    let unload: ((TabID) -> Void)?
    let pullNewIcon: (() -> Void)?
    let restoreSavedLocation: (() -> Void)?
    let promotionNamespace: Namespace.ID?
    /// Whether this row is drawn inside a split group's container rather than
    /// standing on its own in the tab list.
    ///
    /// A grouped row is the same row in every other respect — same height,
    /// favicon, title, trailing control, menu, and selection accent. What it
    /// gives up is the sidebar's edge inset, which the container already
    /// provides, and its reorder source: while tabs are grouped the group moves
    /// as one block, so a member that could be torn out mid-drag would break
    /// the run's contiguity and dissolve the split under the pointer.
    let isSplitGroupMember: Bool

    /// The inset between the row's own bounds and its surface. Zero inside a
    /// group, where the container's padding has already placed the row.
    var surfaceHorizontalInset: CGFloat {
        isSplitGroupMember ? 0 : SidebarTabRowMetrics.surfaceHorizontalInset
    }

    var isReorderSource: Bool {
        !isSplitGroupMember
    }

    var dropLocation: BrowserTabDropLocation {
        BrowserTabDropLocation(
            placement: tab.placement,
            folderID: tab.folderID,
            beforeTabID: tab.id,
            destinationAssignment: assignment
        )
    }

    var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: profileID)
    }

    var isCurrentAndUnlocked: Bool {
        guard
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: assignment,
                in: browser,
                accessController: spaceAccess
            )
        else { return false }
        return space.tabs.contains(where: { $0.id == tab.id })
    }
}
