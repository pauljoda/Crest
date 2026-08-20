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

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)
            .contentShape(.rect)
            .crestInteractiveSurface(
                isSelected: configuration.isSelected,
                isHovering: interaction.isHovering.wrappedValue,
                cornerRadius: CrestLayout.sidebarControlCornerRadius
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
                    && configuration.isCurrentAndUnlocked
                    && configuration.isReorderSource
            )
            .modifier(
                BrowserSidebarTabRowDropIndicators(
                    configuration: configuration,
                    isDropTargeted: interaction.isDropTargeted.wrappedValue,
                    dropTargetHeight: interaction.dropTargetHeight
                )
            )
            .crestCollectionItemTransition()
            .accessibilityElement(children: .contain)
            .contextMenu { organizationMenu }
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
            renameTab: interaction.beginRenaming
        )
        .tint(.primary)
        .onAppear {
            configuration.browser.tabDragState.contextMenuDidOpen(
                for: configuration.runtimeAssignment
            )
        }
        .onDisappear {
            configuration.browser.tabDragState.contextMenuDidClose(
                for: configuration.runtimeAssignment
            )
        }
    }

    private var minHeight: CGFloat {
        BrowserSidebarInteractionPolicy.rowMinHeight(
            configuration.capabilities,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    private var usesMatchedGeometryPromotion: Bool {
        BrowserSidebarInteractionPolicy.usesMatchedGeometryPromotionDestination(
            configuration.capabilities
        )
    }
}
