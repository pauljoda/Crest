import SwiftUI

struct MobileCurrentTabsDropSection: View {
    let space: BrowserSpace
    let tabs: [BrowserTab]
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let spaceAccess: BrowserSpaceAccessController
    let selectTab: (TabID) -> Void
    let openNewTab: () -> Void
    let tabPromotionNamespace: Namespace.ID
    let usesNativeNavigationTransition: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isDropTargeted = false

    var body: some View {
        let followingTabIDs = BrowserTabRowInsertionPolicy.followingTabIDs(in: tabs)
        let items = BrowserSidebarTabListItemPolicy.items(for: tabs)

        VStack(spacing: 0) {
            Button {
                guard isCurrentAndUnlocked else { return }
                openNewTab()
            } label: {
                Label("New Tab", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 56 : 44)
            .accessibilityIdentifier("new-tab")

            ForEach(items) { item in
                switch item {
                case .tab(let tab):
                    let followingTabID = followingTabIDs[tab.id]
                    MobileSidebarTabRow(
                        tab: tab,
                        followingTabID: followingTabID,
                        hasVisibleFollowingRow: followingTabID != nil,
                        spaceID: space.id,
                        profileID: space.profile.id,
                        isSelected: tab.id == space.selectedTabID,
                        canClose: true,
                        browser: browser,
                        spaceAccess: spaceAccess,
                        isLoaded: pages.containsResidentPage(for: tab.id),
                        unload: { tabID in
                            pages.unloadPage(for: tabID, matching: assignment)
                        },
                        pullNewIcon: { pullNewIcon(tab.id) },
                        promotionNamespace: tabPromotionNamespace,
                        usesNativeNavigationTransition: usesNativeNavigationTransition,
                        select: selectTab
                    )
                    .id(tab.id)
                case .splitGroup(let groupID, let members):
                    let followingTabID = members.last.flatMap {
                        followingTabIDs[$0.id]
                    }
                    MobileSidebarSplitGroupRow(
                        groupID: groupID,
                        members: members,
                        followingTabID: followingTabID,
                        hasVisibleFollowingRow: followingTabID != nil,
                        spaceID: space.id,
                        profileID: space.profile.id,
                        selectedTabID: space.selectedTabID,
                        canClose: true,
                        browser: browser,
                        spaceAccess: spaceAccess,
                        isLoaded: { pages.containsResidentPage(for: $0) },
                        promotionNamespace: tabPromotionNamespace,
                        usesNativeNavigationTransition: usesNativeNavigationTransition,
                        select: selectTab
                    )
                }
            }

            // Also the band a cleared list draws its insertion line in: it sits
            // directly below the new-tab row, where the first current tab would
            // appear.
            MobileCurrentTabsEndDropTarget(
                tabs: tabs,
                browser: browser,
                isTargeted: $isDropTargeted,
                move: move
            )
            .browserSidebarReorderSectionIndicator(
                .tabs(placement: .current, folderID: nil),
                state: browser.sidebarReorderState
            )
        }
        .crestCollectionMotion(ids: items.map(\.id))
        .browserSidebarReorderZone(
            .section(.tabs(placement: .current, folderID: nil)),
            state: browser.sidebarReorderState
        )
    }

    private func move(_ item: BrowserTabDragItem, before tabID: TabID?) -> Bool {
        guard isCurrentAndUnlocked else { return false }
        return BrowserTabDragAction(
            browser: browser,
            spaceAccess: spaceAccess
        ).move(
            item,
            to: .current,
            before: tabID,
            matching: assignment
        )
    }

    private func pullNewIcon(_ tabID: TabID) {
        let actions = MobileBrowserSidebarTabActions(
            assignment: assignment,
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess
        )
        Task {
            await actions.pullNewIcon(for: tabID)
        }
    }

    private var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(space: space)
    }

    private var isCurrentAndUnlocked: Bool {
        BrowserSidebarAccessPolicy.selectedUnlockedSpace(
            matching: assignment,
            in: browser,
            accessController: spaceAccess
        ) != nil
    }
}

#Preview("Current Tabs Section") {
    @Previewable @Namespace var promotionNamespace
    let fixture = MobileBrowserSidebarPreviewFixture()

    MobileCurrentTabsDropSection(
        space: fixture.space,
        tabs: fixture.space.currentTabs,
        browser: fixture.browser,
        pages: fixture.pages,
        spaceAccess: fixture.spaceAccess,
        selectTab: { _ in },
        openNewTab: {},
        tabPromotionNamespace: promotionNamespace,
        usesNativeNavigationTransition: false
    )
    .frame(width: 360)
}
