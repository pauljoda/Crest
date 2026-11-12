import SwiftUI

/// Wears a folder's surface in the split's own color, shown as a folder's is,
/// and measures the split as one insertion slot; its header owns the group
/// drag.
struct BrowserSidebarSplitGroupRowSurface: ViewModifier {
    let configuration: BrowserSidebarSplitGroupRowConfiguration
    let interaction: BrowserSidebarSplitGroupRowInteractionContext

    @Environment(\.sidebarLayerDepth) private var depth

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .modifier(
                BrowserFolderSectionSurface(
                    color: configuration.tint ?? .folderDefault,
                    intensity: configuration.displayBranding?.folderColorIntensity ?? 0,
                    textColorMode: configuration.displayBranding?.shownTextColorMode ?? .automatic,
                    depth: depth,
                    isSelected: isMultiSelected,
                    folderID: nil,
                    reorder: configuration.sidebarInteraction.sidebarReorderState,
                    insetsSurface: false)
            )
            // In the same column as every other layer, with the space it keeps
            // from its neighbours inside the row, so drag geometry includes the
            // resting separation.
            .padding(.horizontal, BrowserSidebarMetrics.layerInset)
            .padding(.vertical, BrowserSidebarMetrics.containerSpacing)
            .contentShape(.rect)
            .modifier(
                BrowserTabSelectionTarget(
                    tabID: configuration.members.first?.id, browser: configuration.browser,
                    assignment: configuration.assignment,
                    isEnabled: configuration.isAvailableForDisplay && !interaction.isRenaming)
            )
            .browserSidebarReorderContainer(
                item: .splitGroup(configuration.dragItem),
                section: .tabs(placement: configuration.placement, folderID: configuration.folderID),
                reorder: configuration.reorderContext,
                isEnabled: configuration.isAvailableForDisplay && configuration.capabilities.supportsOrganization
            )
            .crestCollectionItemTransition()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                "Split View with \(configuration.members.count) tabs"
            )
    }

    private var isMultiSelected: Bool {
        configuration.members.contains {
            BrowserSidebarSelection.showsSelected(.tab($0.id), in: configuration.context)
        }
    }

}
