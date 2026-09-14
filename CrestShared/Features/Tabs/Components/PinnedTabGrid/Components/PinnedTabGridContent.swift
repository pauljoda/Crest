import SwiftUI

struct PinnedTabGridContent: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction: BrowserSidebarInteractionState?
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
    var capabilities = BrowserInteractionCapabilities()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTrailingDropTargeted = false
    @State private var renamingAssignment: BrowserTabRuntimeAssignment?
    @State private var iconRequest: BrowserTabRuntimeAssignment?
    @State private var draftTitle = ""
    @AppStorage(BrowserSidebarDensityPreference.scaleKey, store: BrowserSidebarDensityPreference.defaults) private
        var tabScale = 1.0
    @AppStorage(BrowserSidebarDensityPreference.pinColumnsKey, store: BrowserSidebarDensityPreference.defaults) private
        var pinColumns = 0

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
        capabilities = grid.capabilities
    }

    private var reorderContext: BrowserSidebarReorderContext? {
        guard
            BrowserSidebarReorderAvailability.isEnabled,
            capabilities.supportsOrganization,
            let browser,
            let sidebarInteraction,
            let spaceAccess
        else { return nil }
        return BrowserSidebarReorderContext(
            browser: browser,
            spaceAccess: spaceAccess,
            state: sidebarInteraction.sidebarReorderState
        )
    }

    var body: some View {
        BrowserPinnedTabSlotLayout(projection: projection) {
            ForEach(tabs) { tab in
                let runtimeAssignment = runtimeAssignment(for: tab.id)
                let loaded = isLoaded(runtimeAssignment)

                PinnedTabSelectionButton(
                    tab: tab,
                    spaceID: assignment.spaceID,
                    profileID: assignment.profileID,
                    isSelected: tab.id == selectedTabID,
                    isLoaded: loaded,
                    siteTheme: tab.iconMode == .automatic
                        ? (siteThemeAccent(runtimeAssignment) ?? tab.iconAccent)
                        : tab.iconAccent,
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
                    },
                    isMultiSelected: browser?.tabMultiSelection.contains(tab.id) == true,
                    branding: browser?.space(matching: assignment)?.branding,
                    iconCustomization: iconCustomization(for: tab)
                )
                .browserPinnedTabPromotionDestination(
                    id: BrowserTabPromotionID.value(for: tab.id),
                    in: promotionNamespace,
                    anchor: BrowserPinnedTabPromotionPolicy.anchor(
                        hasNamespace: promotionNamespace != nil,
                        isTransitionSource: tab.id == selectedTabID,
                        capabilities: capabilities
                    )
                )
                .accessibilityLabel(tab.displayTitle)
                .accessibilityValue(BrowserChromeAccessibility.tabValue(isLoaded: loaded))
                .accessibilityAddTraits(tab.id == selectedTabID ? .isSelected : [])
                .help(tab.displayTitle)
                .modifier(
                    BrowserTabSelectionAccessibility(
                        tabID: tab.id, spaceID: assignment.spaceID, browser: browser,
                        isActive: tab.id == selectedTabID, isLoaded: loaded)
                )
                .modifier(
                    BrowserTabSelectionTarget(
                        tabID: tab.id, browser: browser, assignment: assignment,
                        isEnabled: isCurrentAndUnlocked(runtimeAssignment))
                )
                .phaseAnimator(
                    [0.0, -4.0, 4.0, -3.0, 3.0, 0.0],
                    trigger: browser?.tabMultiSelection.pinnedRejectionGeneration ?? 0
                ) { content, offset in
                    content.offset(
                        x: !reduceMotion && browser?.tabMultiSelection.rejectedPinnedIDs.contains(tab.id) == true
                            ? offset : 0)
                } animation: { _ in
                    .linear(duration: 0.055)
                }
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
                    if capabilities.supportsOrganization, let browser, let spaceAccess {
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
                            renameTab: { beginRenaming(tab) },
                            changeIcon: { beginChangingIcon(runtimeAssignment) }
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
            RoundedRectangle(cornerRadius: BrowserDeviceAppearanceStore.shared.sidebarCornerRadius, style: .continuous)
                .fill(.primary.opacity(0.035))
                .overlay {
                    RoundedRectangle(
                        cornerRadius: BrowserDeviceAppearanceStore.shared.sidebarCornerRadius, style: .continuous
                    )
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                }
                .opacity(projection.insertionIndex == nil ? 0 : 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .animation(
            BrowserVisualAccessibilityPolicy.animation(CrestMotion.dragSource, reduceMotion: reduceMotion),
            value: projection.slots
        )
        .environment(\.browserInteractionCapabilities, capabilities)
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
        .onChange(of: iconRequestIsLive) { _, isLive in
            guard !isLive else { return }
            iconRequest = nil
        }
        .onChange(of: assignment) { _, _ in iconRequest = nil }
        .onDisappear { iconRequest = nil }
    }

    private var iconActions: BrowserTabOrganizationAction? {
        guard let browser, let spaceAccess else { return nil }
        return BrowserTabOrganizationAction(browser: browser, spaceAccess: spaceAccess)
    }

    private var iconRequestIsLive: Bool {
        guard let iconRequest,
            iconRequest.spaceID == assignment.spaceID,
            iconRequest.profileID == assignment.profileID,
            capabilities.supportsOrganization
        else { return false }
        return iconActions?.canCustomizePinnedIcon(for: iconRequest) == true
    }

    private func beginChangingIcon(_ request: BrowserTabRuntimeAssignment) {
        guard capabilities.supportsOrganization,
            iconActions?.canCustomizePinnedIcon(for: request) == true
        else { return }
        iconRequest = request
    }

    private func iconCustomization(for tab: BrowserTab) -> BrowserIconCustomizationPresentation {
        let request = runtimeAssignment(for: tab.id)
        return BrowserIconCustomizationPresentation(
            isPresented: Binding(
                get: { iconRequest == request && iconRequestIsLive },
                set: { isPresented in
                    if isPresented {
                        beginChangingIcon(request)
                    } else if iconRequest == request {
                        iconRequest = nil
                    }
                }
            ),
            title: "Tab Icon",
            currentEmoji: tab.emojiIcon,
            showsReset: BrowserTabIconCustomizationPolicy.showsReset(for: tab),
            resetTitle: "Use Website Icon",
            setEmoji: { emoji in
                guard iconRequest == request, iconRequestIsLive else { return }
                iconActions?.setPinnedTabEmoji(emoji, for: request)
            },
            reset: {
                guard iconRequest == request, iconRequestIsLive else { return }
                iconActions?.clearPinnedTabIcon(for: request)
            }
        )
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

    private var projection: BrowserPinnedTabReorderLayout {
        let ids = tabs.map { BrowserSidebarReorderItemID.tab($0.id) }
        var value =
            (reorderContext?.state.pinnedLayout(ids: ids, in: assignment) ?? BrowserPinnedTabReorderLayout(ids: ids))
            .applyingPreferences(width: BrowserChromeLayout.sidebarIdealWidth, touch: capabilities.supportsTouch)
        value.preferredColumns = min(max(pinColumns, 0), 6)
        value.tabScale = tabScale
        value.tileHeight = BrowserSidebarDensityPolicy.pinHeight(scale: tabScale, touch: capabilities.supportsTouch)
        value.tileSpacing = BrowserSidebarDensityPolicy.pinSpacing(scale: tabScale)
        return value
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
