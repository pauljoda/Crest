import SwiftUI

/// A split group as one sidebar row: a grouped surface holding the count
/// affordance and one ordinary tab row per member.
///
/// The members are not a compact imitation of a tab row — they are
/// `BrowserSidebarTabRow`, the same view the rest of the list draws, so a split reads
/// as tabs that have been gathered rather than as a widget that replaced them.
/// The container carries what belongs to the group — presented, dragged, and
/// the two ways a split ends — and each row carries what belongs to its own
/// tab. That division is what lets a group be one row to the list while still
/// letting a person focus, rename, unload, or close one pane.
struct SidebarSplitGroupRow: View {
    let groupID: SplitGroupID
    let members: [BrowserTab]
    let spaceID: SpaceID
    let profileID: UUID
    let selectedTabID: TabID?
    let canClose: Bool
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    var presentSelectedPage: () -> Void = {}
    var isLoaded: (TabID) -> Bool = { _ in true }
    var unload: ((TabID) -> Void)? = nil
    var pullNewIcon: ((TabID) -> Void)? = nil
    var restoreSavedLocation: ((TabID) -> Void)? = nil

    var body: some View {
        SidebarSplitGroupRowContent(configuration: configuration)
            .modifier(SidebarSplitGroupRowSurface(configuration: configuration))
    }

    private var configuration: SidebarSplitGroupRowConfiguration {
        SidebarSplitGroupRowConfiguration(
            groupID: groupID,
            members: members,
            spaceID: spaceID,
            profileID: profileID,
            selectedTabID: selectedTabID,
            canClose: canClose,
            browser: browser,
            spaceAccess: spaceAccess,
            presentSelectedPage: presentSelectedPage,
            isLoaded: isLoaded,
            unload: unload,
            pullNewIcon: pullNewIcon,
            restoreSavedLocation: restoreSavedLocation
        )
    }
}
