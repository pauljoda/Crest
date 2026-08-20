import SwiftUI
import UniformTypeIdentifiers

/// Everything wrapped around a tab row's content: its band, its selection and
/// hover treatment, and every gesture the row answers.
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
