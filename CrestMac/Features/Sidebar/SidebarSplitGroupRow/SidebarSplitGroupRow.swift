import SwiftUI

/// A split group as one sidebar row: a grouped surface holding the count
/// affordance and one ordinary tab row per member.
///
/// The members are not a compact imitation of a tab row — they are
/// `SidebarTabRow`, the same view the rest of the list draws, so a split reads
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

/// Every renderable size, presented and not, against the tab rows they sit
/// between — the comparison that says whether a group still reads as one row.
#Preview("Split Group Row — Current Tabs") {
    let configurations = SidebarSplitGroupRowPreviewFixture.configurations(
        memberCounts: [2, 3, 4],
        selectedIndexes: [1, nil]
    )

    ScrollView {
        VStack(spacing: 0) {
            ForEach(configurations.indices, id: \.self) { index in
                let configuration = configurations[index]

                SidebarSplitGroupRow(
                    groupID: configuration.groupID,
                    members: configuration.members,
                    spaceID: configuration.spaceID,
                    profileID: configuration.profileID,
                    selectedTabID: configuration.selectedTabID,
                    canClose: configuration.canClose,
                    browser: configuration.browser,
                    spaceAccess: configuration.spaceAccess
                )

                SidebarTabRow(
                    tab: SidebarSplitGroupRowPreviewFixture.neighborTab(),
                    spaceID: configuration.spaceID,
                    profileID: configuration.profileID,
                    isSelected: false,
                    canClose: configuration.canClose,
                    browser: configuration.browser,
                    spaceAccess: configuration.spaceAccess
                )
            }
        }
        .padding(.vertical)
    }
    .frame(width: BrowserChromeLayout.sidebarIdealWidth, height: 720)
}

/// Saved placement: `canClose` is false there, so a member's trailing control
/// is the unload button rather than a close X.
#Preview("Split Group Row — Saved Tabs") {
    let configurations = SidebarSplitGroupRowPreviewFixture.configurations(
        memberCounts: [2, 3],
        selectedIndexes: [0, nil],
        placement: .saved
    )

    VStack(spacing: 0) {
        ForEach(configurations.indices, id: \.self) { index in
            let configuration = configurations[index]

            SidebarSplitGroupRow(
                groupID: configuration.groupID,
                members: configuration.members,
                spaceID: configuration.spaceID,
                profileID: configuration.profileID,
                selectedTabID: configuration.selectedTabID,
                canClose: configuration.canClose,
                browser: configuration.browser,
                spaceAccess: configuration.spaceAccess,
                unload: { _ in }
            )
        }
    }
    .frame(width: BrowserChromeLayout.sidebarIdealWidth)
    .padding(.vertical)
}
