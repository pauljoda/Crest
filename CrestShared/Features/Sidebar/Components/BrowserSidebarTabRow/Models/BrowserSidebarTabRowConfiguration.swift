import SwiftUI

/// Everything a sidebar tab row is told, and the answers that follow from it.
@MainActor
struct BrowserSidebarTabRowConfiguration {
    let tab: BrowserTab
    let spaceID: SpaceID
    let profileID: UUID
    let isSelected: Bool
    let canClose: Bool
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let capabilities: BrowserInteractionCapabilities
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
    /// provides.
    let isSplitGroupMember: Bool
    /// Whether the row registers itself as something a reorder can lift.
    ///
    /// A split group's members stand this down: while tabs are grouped the
    /// group moves as one block, so a member that could be torn out mid-drag
    /// would break the run's contiguity and dissolve the split under the
    /// pointer.
    let isReorderSource: Bool
    let followingTabID: TabID?
    let hasVisibleFollowingRow: Bool
    let select: (TabID) -> Void

    var metrics: BrowserSidebarTabRowMetrics {
        BrowserSidebarInteractionPolicy.tabRowMetrics(capabilities)
    }

    var trailingControlMetrics: BrowserTabTrailingControlMetrics {
        BrowserSidebarInteractionPolicy.trailingControlMetrics(capabilities)
    }

    /// The inset between the row's own bounds and its surface. Zero inside a
    /// group, where the container's padding has already placed the row.
    var surfaceHorizontalInset: CGFloat {
        isSplitGroupMember ? 0 : metrics.surfaceHorizontalInset
    }

    /// Whether this row draws its own insertion lines.
    ///
    /// A grouped member never does, whatever the shell can show. The container
    /// is one row to the list and owns both anchors for the whole run, and a
    /// member drawing its own would double the line above the first member and
    /// light one up under *every* member for a drop aimed at the end of the
    /// section — neither of which is a place a tab can actually land.
    var showsDropIndicators: Bool {
        capabilities.showsRowDropIndicators && !isSplitGroupMember
    }

    /// The identity this row shares with the surface its page grows out of.
    var promotionID: String {
        BrowserTabPromotionID.value(for: tab.id)
    }

    var isPromotionSource: Bool {
        BrowserTabPromotionSourcePolicy.isPromotionSource(
            tab,
            isSelected: isSelected
        )
    }

    var beforeDropLocation: BrowserTabDropLocation {
        BrowserTabDropLocation(
            placement: tab.placement,
            folderID: tab.folderID,
            beforeTabID: tab.id,
            destinationAssignment: assignment
        )
    }

    var afterDropLocation: BrowserTabDropLocation {
        BrowserTabDropLocation(
            placement: tab.placement,
            folderID: tab.folderID,
            beforeTabID: followingTabID,
            destinationAssignment: assignment
        )
    }

    var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: profileID)
    }

    var runtimeAssignment: BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(
            tabID: tab.id,
            spaceID: spaceID,
            profileID: profileID
        )
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
