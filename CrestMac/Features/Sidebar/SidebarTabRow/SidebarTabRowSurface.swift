import SwiftUI
import UniformTypeIdentifiers

struct SidebarTabRowSurface: ViewModifier {
    let configuration: SidebarTabRowConfiguration
    let interaction: SidebarTabRowInteractionContext

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: CrestLayout.sidebarRowHeight)
            .contentShape(.rect)
            .crestInteractiveSurface(
                isSelected: configuration.isSelected,
                isHovering: interaction.isHovering.wrappedValue,
                cornerRadius: CrestLayout.sidebarControlCornerRadius
            )
            .browserTabPromotionDestination(
                id: "crest-start-page-promotion-\(configuration.tab.id)",
                in: configuration.promotionNamespace
            )
            .padding(.horizontal, configuration.surfaceHorizontalInset)
            .contentShape(.rect)
            .onHover { interaction.isHovering.wrappedValue = $0 }
            .browserOnMiddleClick(
                perform: interaction.dismissFromMiddleClick
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
            .crestCollectionItemTransition()
            .accessibilityElement(children: .contain)
            .contextMenu {
                BrowserTabOrganizationMenu(
                    tab: configuration.tab,
                    assignment: BrowserTabRuntimeAssignment(
                        tabID: configuration.tab.id,
                        spaceID: configuration.spaceID,
                        profileID: configuration.profileID
                    ),
                    browser: configuration.browser,
                    spaceAccess: configuration.spaceAccess,
                    isLoaded: configuration.isLoaded,
                    unload: configuration.unload,
                    pullNewIcon: configuration.pullNewIcon,
                    restoreSavedLocation: configuration.restoreSavedLocation,
                    renameTab: interaction.beginRenaming
                )
                .tint(.primary)
            }
            .onChange(of: interaction.isTitleFocused.wrappedValue) { _, focused in
                if !focused, interaction.isRenaming {
                    interaction.commitTitle()
                }
            }
    }
}

extension View {
    @ViewBuilder
    func browserTabPromotionDestination(
        id: String,
        in namespace: Namespace.ID?
    ) -> some View {
        if let namespace {
            matchedGeometryEffect(
                id: id,
                in: namespace,
                properties: .frame,
                anchor: .center,
                isSource: false
            )
        } else {
            self
        }
    }
}
