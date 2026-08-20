import SwiftUI

/// A split group as one sidebar row, on every shell: a grouped surface holding
/// the count affordance and one ordinary tab row per member.
///
/// The members are not a compact imitation of a tab row — they are
/// `BrowserSidebarTabRow`, the same view the rest of the list draws, so a split
/// reads as tabs that have been gathered rather than as a widget that replaced
/// them. The container carries what belongs to the group — presented, dragged,
/// dropped against, and the two ways a split ends — and each row carries what
/// belongs to its own tab. That division is what lets a group be one row to the
/// list while still letting a person focus, rename, unload, or close one pane.
///
/// What differs between a pointer shell and a touch one is read from
/// `BrowserSidebarInteractionPolicy` rather than from which target compiled the
/// file, so the two shells share this row instead of a resemblance.
struct BrowserSidebarSplitGroupRow: View {
    let groupID: SplitGroupID
    let members: [BrowserTab]
    let spaceID: SpaceID
    let profileID: UUID
    let selectedTabID: TabID?
    let canClose: Bool
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let capabilities: BrowserInteractionCapabilities
    var isLoaded: (TabID) -> Bool = { _ in true }
    var unload: ((TabID) -> Void)? = nil
    var pullNewIcon: ((TabID) -> Void)? = nil
    var restoreSavedLocation: ((TabID) -> Void)? = nil
    var promotionNamespace: Namespace.ID? = nil
    /// The row a drop below this group would land in front of, skipping past
    /// the whole run. Only read where the shell draws its insertion line on the
    /// rows themselves.
    var followingTabID: TabID? = nil
    var hasVisibleFollowingRow = false
    /// What opening a member means to the host, matching the tab row: the group
    /// decides *whether* and *which*, the host decides what appears.
    let select: (TabID) -> Void

    var body: some View {
        BrowserSidebarSplitGroupRowContent(configuration: configuration)
            .modifier(
                BrowserSidebarSplitGroupRowSurface(configuration: configuration)
            )
    }

    private var configuration: BrowserSidebarSplitGroupRowConfiguration {
        BrowserSidebarSplitGroupRowConfiguration(
            groupID: groupID,
            members: members,
            spaceID: spaceID,
            profileID: profileID,
            selectedTabID: selectedTabID,
            canClose: canClose,
            browser: browser,
            spaceAccess: spaceAccess,
            capabilities: capabilities,
            isLoaded: isLoaded,
            unload: unload,
            pullNewIcon: pullNewIcon,
            restoreSavedLocation: restoreSavedLocation,
            promotionNamespace: promotionNamespace,
            followingTabID: followingTabID,
            hasVisibleFollowingRow: hasVisibleFollowingRow,
            select: select
        )
    }
}
