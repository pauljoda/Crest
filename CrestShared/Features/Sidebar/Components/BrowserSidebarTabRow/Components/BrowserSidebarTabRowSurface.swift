import SwiftUI
import UniformTypeIdentifiers

/// Everything wrapped around a tab row's content: its band, its selection and
/// hover treatment, and every gesture the row answers.
///
/// Two things about this chain are load-bearing and invisible in the code.
///
/// **The lift is armed before the menu.** `browserTabDraggable` must stay above
/// `contextMenu`. On a touch shell the lift *is* drag-and-drop —
/// `UIContextMenuInteraction` cancels any gesture that competes with it, so
/// drag-and-drop is the only path the system arbitrates against a menu — and the
/// row is the view that carries both. Move the menu under the drag source and
/// holding a row raises the menu with nothing left to pull.
///
/// **A row claims at most one promotion anchor.** The pairing below is an
/// either/or: `browserTabPromotionDestination` for a shell that grows a surface
/// out of the row through matched geometry, `BrowserPlatformTabPromotionSource`
/// for one that pushes a page with the system's navigation zoom. Both anchor the
/// same identity, and both are presentation transforms over the exact view the
/// drag interaction lifts. Two of them, or one with no partner to pair with, and
/// the lift stops starting — which is what
/// `BrowserSidebarInteractionPolicy.usesMatchedGeometryPromotionDestination` and
/// `BrowserInteractionCapabilities.pairsRowWithPromotedSurface` exist to keep
/// from happening.
struct BrowserSidebarTabRowSurface: ViewModifier {
    let configuration: BrowserSidebarTabRowConfiguration
    let interaction: BrowserSidebarTabRowInteractionContext

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(BrowserSidebarDensityPreference.scaleKey, store: BrowserSidebarDensityPreference.defaults)
    private var tabScale = 1.0

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)
            .contentShape(.rect)
            .modifier(
                BrowserTabAppearanceSurface(
                    appearance: BrowserDeviceAppearanceStore.shared.tabs,
                    accent: (BrowserDeviceAppearanceStore.shared.tabs.color ?? branding?.primaryColor ?? .indigo).color,
                    isPinned: false,
                    isSelected: configuration.isSelected,
                    isHovering: interaction.isHovering.wrappedValue
                        || (configuration.tab.splitGroupID == nil
                            && configuration.browser.tabMultiSelection.contains(configuration.tab.id)
                            && !BrowserSidebarSelection.isCoveredBySelectedFolder(
                                .tab(configuration.tab.id), in: configuration.browser))
                )
            )
            .padding(
                .vertical,
                BrowserSidebarDensityPolicy.rowSeparation(
                    scale: tabScale, hasBorders: BrowserDeviceAppearanceStore.shared.tabs.borders == .all) / 2
            )
            .browserTabPromotionDestination(
                id: configuration.promotionID,
                in: configuration.promotionNamespace,
                isActive: usesMatchedGeometryPromotion
            )
            .modifier(
                BrowserPlatformTabPromotionSourceModifier(
                    id: configuration.promotionID,
                    namespace: configuration.promotionNamespace,
                    usesNativeNavigationTransition:
                        configuration.capabilities.usesNativeNavigationTransition,
                    isEnabled: configuration.isPromotionSource
                )
            )
            .padding(.horizontal, configuration.surfaceHorizontalInset)
            .modifier(
                BrowserTabSelectionTarget(
                    tabID: configuration.tab.id, browser: configuration.browser,
                    assignment: BrowserSpaceRuntimeAssignment(
                        spaceID: configuration.spaceID, profileID: configuration.profileID),
                    isEnabled: configuration.isAvailableForDisplay && !interaction.isRenaming)
            )
            .contentShape(.rect)
            .onHover { interaction.isHovering.wrappedValue = $0 }
            .modifier(
                BrowserPlatformRowAuxiliaryClickModifier(
                    perform: interaction.dismissFromAuxiliaryClick
                )
            )
            .browserTabDraggable(
                tab: configuration.tab,
                profileID: configuration.profileID,
                spaceID: configuration.spaceID,
                dragState: configuration.browser.tabDragState,
                reorder: BrowserSidebarReorderContext(
                    browser: configuration.browser,
                    spaceAccess: configuration.spaceAccess
                ),
                // Disabled means no lift gesture *and* no registered reorder
                // frame, so a grouped member neither drags out on its own nor
                // offers a drop slot between two members of its own run.
                isEnabled: !interaction.isRenaming
                    && configuration.isAvailableForDisplay
                    && configuration.isReorderSource
                    && configuration.capabilities.supportsOrganization,
                requiresSelectedSpace: true
            )
            .modifier(
                BrowserSidebarTabRowDropIndicators(
                    configuration: configuration,
                    isDropTargeted: interaction.isDropTargeted.wrappedValue,
                    dropTargetHeight: interaction.dropTargetHeight
                )
            )
            .browserSidebarReorderZone(
                .currentTab(configuration.tab.id),
                state: configuration.browser.sidebarReorderState,
                isActive: configuration.tab.placement == .current
                    && configuration.tab.folderID == nil
                    && configuration.tab.splitGroupID == nil
                    && configuration.isAvailableForDisplay,
                requiresSelectedSpace: true
            )
            .overlay {
                BrowserFolderNestDropHighlight(
                    isTargeted: configuration.browser.sidebarReorderState.resolvedTarget?.kind
                        == .createCurrentFolder(configuration.tab.id)
                )
                .allowsHitTesting(false)
            }
            .crestCollectionItemTransition()
            .accessibilityElement(children: .contain)
            .contextMenu {
                if configuration.capabilities.supportsOrganization { organizationMenu }
            }
            .onChange(of: interaction.isTitleFocused.wrappedValue) { _, focused in
                if !focused, interaction.isRenaming {
                    interaction.commitTitle()
                }
            }
    }

    /// Opening the menu ends any drag the same row had started. The lift and
    /// the long press are the same gesture up to the moment one of them wins,
    /// and a menu that opens over a live drag leaves the list mid-reorder.
    private var organizationMenu: some View {
        BrowserTabOrganizationMenu(
            tab: configuration.tab,
            assignment: configuration.runtimeAssignment,
            browser: configuration.browser,
            spaceAccess: configuration.spaceAccess,
            isLoaded: configuration.isLoaded,
            unload: configuration.unload,
            pullNewIcon: configuration.pullNewIcon,
            restoreSavedLocation: configuration.restoreSavedLocation,
            renameTab: interaction.beginRenaming,
            changeIcon: interaction.beginChangingIcon
        )
        .tint(.primary)
        .onAppear {
            configuration.browser.tabDragState.contextMenuDidOpen(
                for: configuration.runtimeAssignment
            )
            // Both states, because the two lifts are different machines: the
            // pointer drag reports through `tabDragState`, and the touch lift
            // through the reorder state, which has no session left to hear
            // from once this menu has the press.
            configuration.browser.sidebarReorderState
                .yieldToCompetingInteraction()
        }
        .onDisappear {
            configuration.browser.tabDragState.contextMenuDidClose(
                for: configuration.runtimeAssignment
            )
        }
    }

    private var minHeight: CGFloat {
        let base = BrowserSidebarInteractionPolicy.rowMinHeight(
            configuration.capabilities,
            dynamicTypeSize: dynamicTypeSize
        )
        return BrowserSidebarDensityPolicy.rowHeight(
            base: base, scale: dynamicTypeSize.isAccessibilitySize ? max(1, tabScale) : tabScale,
            touch: configuration.capabilities.supportsTouch)
    }

    private var branding: BrowserSpaceBranding? {
        configuration.spacePresentation?.branding
            ?? configuration.browser.session.space(id: configuration.spaceID)?.branding
    }

    private var usesMatchedGeometryPromotion: Bool {
        BrowserSidebarInteractionPolicy.usesMatchedGeometryPromotionDestination(
            configuration.capabilities
        )
    }
}
