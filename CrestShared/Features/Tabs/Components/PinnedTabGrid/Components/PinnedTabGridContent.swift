import SwiftUI

struct PinnedTabGridContent: View {
    let tabs: [BrowserTab]
    let assignment: BrowserSpaceRuntimeAssignment
    let selectedTabID: TabID?
    let select: (BrowserTabRuntimeAssignment) -> Void
    var moveTab: ((BrowserTabDragItem, TabID?) -> Bool)? = nil
    var dragState: BrowserTabDragState? = nil
    var browser: BrowserStore? = nil
    var spaceAccess: BrowserSpaceAccessController? = nil
    var isLoaded: (BrowserTabRuntimeAssignment) -> Bool = { _ in true }
    var unload: ((BrowserTabRuntimeAssignment) -> Void)? = nil
    var pullNewIcon: ((BrowserTabRuntimeAssignment) -> Void)? = nil
    var restoreSavedLocation: ((BrowserTabRuntimeAssignment) -> Void)? = nil
    var siteThemeAccent: (BrowserTabRuntimeAssignment) -> BrowserTabIconAccent? = {
        _ in nil
    }
    var promotionNamespace: Namespace.ID? = nil
    var usesNativeNavigationTransition = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTrailingDropTargeted = false
    @State private var renamingAssignment: BrowserTabRuntimeAssignment?
    @State private var draftTitle = ""

    init(grid: PinnedTabGrid) {
        tabs = grid.tabs
        assignment = grid.assignment
        selectedTabID = grid.selectedTabID
        select = grid.select
        moveTab = grid.moveTab
        dragState = grid.dragState
        browser = grid.browser
        spaceAccess = grid.spaceAccess
        isLoaded = grid.isLoaded
        unload = grid.unload
        pullNewIcon = grid.pullNewIcon
        restoreSavedLocation = grid.restoreSavedLocation
        siteThemeAccent = grid.siteThemeAccent
        promotionNamespace = grid.promotionNamespace
        usesNativeNavigationTransition = grid.usesNativeNavigationTransition
    }

    private var reorderContext: BrowserSidebarReorderContext? {
        guard
            BrowserSidebarReorderAvailability.isEnabled,
            let browser,
            let spaceAccess
        else { return nil }
        return BrowserSidebarReorderContext(
            browser: browser,
            spaceAccess: spaceAccess
        )
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: CrestSpacing.small) {
            ForEach(tabs) { tab in
                let runtimeAssignment = runtimeAssignment(for: tab.id)
                let loaded = isLoaded(runtimeAssignment)

                PinnedTabSelectionButton(
                    tab: tab,
                    profileID: assignment.profileID,
                    isSelected: tab.id == selectedTabID,
                    isLoaded: loaded,
                    siteTheme: siteThemeAccent(runtimeAssignment),
                    select: {
                        guard isCurrentAndUnlocked(runtimeAssignment) else { return }
                        // The touch-up that ends a lift also reaches this button;
                        // opening the tile that was just dragged is not a select.
                        if let reorderContext,
                            reorderContext.state.suppressesActivation
                        {
                            return
                        }
                        select(runtimeAssignment)
                    }
                )
                .browserPinnedTabPromotionDestination(
                    id: BrowserTabPromotionID.value(for: tab.id),
                    in: promotionNamespace,
                    usesNativeNavigationTransition: usesNativeNavigationTransition,
                    isTransitionSource: tab.id == selectedTabID
                )
                .accessibilityLabel(tab.displayTitle)
                .accessibilityValue(
                    BrowserChromeAccessibility.tabValue(isLoaded: loaded)
                )
                .accessibilityAddTraits(tab.id == selectedTabID ? .isSelected : [])
                .help(tab.displayTitle)
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        guard
                            BrowserPinnedTabInteraction
                                .shouldRestoreSavedLocation(for: tab),
                            isCurrentAndUnlocked(runtimeAssignment)
                        else { return }
                        restoreSavedLocation?(runtimeAssignment)
                    }
                )
                .browserPinnedTabMiddleClick {
                    dismissFromMiddleClick(runtimeAssignment)
                }
                .modifier(
                    PinnedTabDragModifier(
                        tab: tab,
                        assignment: assignment,
                        moveTab: moveTab,
                        dragState: dragState,
                        reorder: reorderContext
                    )
                )
                .contextMenu {
                    if let browser, let spaceAccess {
                        PinnedTabOrganizationMenu(
                            tab: tab,
                            assignment: runtimeAssignment,
                            browser: browser,
                            spaceAccess: spaceAccess,
                            isLoaded: loaded,
                            dragState: dragState,
                            unload: unload,
                            pullNewIcon: pullNewIcon,
                            restoreSavedLocation: restoreSavedLocation,
                            renameTab: { beginRenaming(tab) }
                        )
                    }
                }
                .animation(
                    BrowserVisualAccessibilityPolicy.animation(
                        CrestMotion.contentState,
                        reduceMotion: reduceMotion
                    ),
                    value: loaded
                )
                .crestCollectionItemTransition()
            }
        }
        .crestCollectionMotion(ids: tabs.map(\.id))
        .overlay(alignment: .trailing) {
            if moveTab != nil, let dragState, dragState.item != nil {
                Color.clear
                    .frame(width: BrowserPinnedDropTargetPolicy.trailingTargetWidth)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .accessibilityHidden(true)
            }
        }
        .alert("Rename Tab", isPresented: isRenamingBinding) {
            TextField("Tab Name", text: $draftTitle)
                .accessibilityIdentifier("tab-rename-field")

            Button("Rename", action: commitRename)
                .accessibilityIdentifier("confirm-rename-tab")

            Button("Cancel", role: .cancel) { renamingAssignment = nil }
        }
        .onChange(of: renamingAssignmentIsLive) { _, isLive in
            guard !isLive else { return }
            renamingAssignment = nil
        }
    }

    /// A pinned tile shows an icon and no editable label, so renaming one asks
    /// for the name instead of editing in place the way a sidebar row does.
    private var isRenamingBinding: Binding<Bool> {
        Binding(
            get: { renamingAssignmentIsLive },
            set: { isPresented in
                guard !isPresented else { return }
                renamingAssignment = nil
            }
        )
    }

    private func beginRenaming(_ tab: BrowserTab) {
        let assignment = runtimeAssignment(for: tab.id)
        guard isCurrentAndUnlocked(assignment) else { return }
        draftTitle = tab.displayTitle
        renamingAssignment = assignment
    }

    private func commitRename() {
        guard let renamingAssignment else { return }
        self.renamingAssignment = nil
        guard let browser,
            isCurrentAndUnlocked(renamingAssignment)
        else { return }
        browser.setTabCustomTitle(
            draftTitle,
            for: renamingAssignment.tabID,
            matching: BrowserSpaceRuntimeAssignment(
                spaceID: renamingAssignment.spaceID,
                profileID: renamingAssignment.profileID
            )
        )
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: CrestSpacing.small),
            count: PinnedTabGridLayout.columnCount(for: tabs.count)
        )
    }

    private func dismissFromMiddleClick(
        _ runtimeAssignment: BrowserTabRuntimeAssignment
    ) {
        guard isLoaded(runtimeAssignment),
            isCurrentAndUnlocked(runtimeAssignment)
        else { return }
        unload?(runtimeAssignment)
    }

    private var renamingAssignmentIsLive: Bool {
        guard let renamingAssignment else { return false }
        return isCurrentAndUnlocked(renamingAssignment)
    }

    private func isCurrentAndUnlocked(
        _ assignment: BrowserTabRuntimeAssignment
    ) -> Bool {
        guard let browser, let spaceAccess,
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: BrowserSpaceRuntimeAssignment(
                    spaceID: assignment.spaceID,
                    profileID: assignment.profileID
                ),
                in: browser,
                accessController: spaceAccess
            )
        else { return false }
        return space.tabs.contains(where: { $0.id == assignment.tabID })
    }

    private func runtimeAssignment(
        for tabID: TabID
    ) -> BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(
            tabID: tabID,
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
    }
}
