import SwiftUI

/// A split group as one sidebar row on iPhone and iPad: a grouped surface
/// holding the count affordance and one full-height line per member.
///
/// The container carries the group's state — presented, dropped against — and
/// each line carries its member's. That split is what lets a group read as a
/// single row in the list while still letting a person focus or close one pane
/// with a finger.
struct MobileSidebarSplitGroupRow: View {
    let groupID: SplitGroupID
    let members: [BrowserTab]
    /// The tab following the group's *last* member, or `nil` at the end of the
    /// section. The group is one row, so its trailing drop anchor skips past
    /// every member rather than landing between two of them.
    let followingTabID: TabID?
    let hasVisibleFollowingRow: Bool
    let spaceID: SpaceID
    let profileID: UUID
    let selectedTabID: TabID?
    let canClose: Bool
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    var isLoaded: (TabID) -> Bool = { _ in true }
    var promotionNamespace: Namespace.ID? = nil
    var usesNativeNavigationTransition = false
    let select: (TabID) -> Void

    var body: some View {
        VStack(spacing: MobileSidebarSplitGroupRowMetrics.memberSpacing) {
            MobileSidebarSplitGroupHeader(memberCount: members.count)

            ForEach(members) { member in
                MobileSidebarSplitGroupMemberLine(
                    configuration: configuration,
                    member: member
                )
                // Selecting a member prepositions the sidebar's scroll onto the
                // row it will zoom from, and that row is the member's line.
                .id(member.id)
            }
        }
        .padding(MobileSidebarSplitGroupRowMetrics.containerPadding)
        .frame(maxWidth: .infinity)
        // A resting surface, like a pinned tile's: the container has to read as
        // one grouped thing even when the split is not the presented one, or its
        // member lines look like loose rows that happen to be adjacent.
        .crestInteractiveSurface(
            isSelected: configuration.isPresented,
            isHovering: false,
            cornerRadius: MobileSidebarSplitGroupRowMetrics
                .containerCornerRadius,
            showsRestingSurface: true
        )
        .padding(
            .horizontal,
            MobileSidebarSplitGroupRowMetrics.rowHorizontalInset
        )
        .contentShape(.rect)
        // Registers the whole group as one reorder row and arms its lift. The
        // registration is also what makes a tab dragged past the group step over
        // the run as a single slot instead of landing between two members.
        .browserSplitGroupDraggable(
            item: configuration.dragItem,
            members: members,
            placement: configuration.placement,
            folderID: configuration.folderID,
            reorder: configuration.reorderContext,
            isEnabled: configuration.isCurrentAndUnlocked
        )
        .overlay(alignment: .top) {
            BrowserTabDropIndicator(
                location: configuration.beforeDropLocation,
                dragState: browser.tabDragState,
                isTargeted: false
            )
        }
        .overlay(alignment: .bottom) {
            if BrowserTabRowIndicatorOwnershipPolicy.showsAfterRowIndicator(
                hasVisibleFollowingRow: hasVisibleFollowingRow
            ) {
                BrowserTabDropIndicator(
                    location: configuration.afterDropLocation(
                        followingTabID: followingTabID
                    ),
                    dragState: browser.tabDragState,
                    isTargeted: false
                )
            }
        }
        .crestCollectionItemTransition()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Split View with \(members.count) tabs")
        .contextMenu {
            MobileSidebarSplitGroupContextMenu(configuration: configuration)
                .tint(.primary)
        }
    }

    private var configuration: MobileSidebarSplitGroupRowConfiguration {
        MobileSidebarSplitGroupRowConfiguration(
            groupID: groupID,
            members: members,
            spaceID: spaceID,
            profileID: profileID,
            selectedTabID: selectedTabID,
            canClose: canClose,
            browser: browser,
            spaceAccess: spaceAccess,
            isLoaded: isLoaded,
            promotionNamespace: promotionNamespace,
            usesNativeNavigationTransition: usesNativeNavigationTransition,
            select: select
        )
    }
}
