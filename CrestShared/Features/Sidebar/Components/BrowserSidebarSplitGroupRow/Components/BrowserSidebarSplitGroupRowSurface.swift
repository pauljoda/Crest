import SwiftUI

/// Measures the split as one insertion slot; its header owns the group drag.
struct BrowserSidebarSplitGroupRowSurface: ViewModifier {
    let configuration: BrowserSidebarSplitGroupRowConfiguration
    let interaction: BrowserSidebarSplitGroupRowInteractionContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .background {
                containerShape
                    .fill(groupTint)
                    .overlay { if isMultiSelected { containerShape.fill(CrestColor.hover) } }
                    .overlay {
                        if let tint = configuration.displayMetadata.tint {
                            containerShape.fill(
                                tint.color.opacity(
                                    configuration.isPresented ? 0.16 : 0.10
                                )
                            )
                        }
                    }
            }
            .animation(surfaceAnimation, value: configuration.isPresented)
            .animation(surfaceAnimation, value: isMultiSelected)
            .padding(.horizontal, configuration.rowHorizontalInset)
            .padding(.vertical, configuration.metrics.rowVerticalInset)
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
            .modifier(
                BrowserSidebarSplitGroupRowDropIndicators(
                    configuration: configuration
                )
            )
            .crestCollectionItemTransition()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                "Split View with \(configuration.members.count) tabs"
            )
    }

    /// The container's own tint, and deliberately the quietest of the three
    /// surfaces a presented group shows.
    ///
    /// Members are real tab rows, so the focused one already carries the full
    /// selection treatment — fill, border, and shadow — a container padding
    /// inside this one. Giving the container that same treatment stacked two
    /// bordered, shadowed surfaces almost on top of each other and, worse,
    /// painted the container in the exact fill the focused row uses, which
    /// erased the row it was meant to frame. So the container never takes the
    /// selection: it rests at the grouped chrome tint and lifts one step to the
    /// hover tint while the split is presented. Resting, hovered, selected —
    /// 0.055, 0.08, 0.13 — reads as one ordered hierarchy rather than two
    /// competing ones.
    private var isMultiSelected: Bool {
        configuration.members.contains {
            configuration.browser.tabMultiSelection.contains($0.id)
                && !BrowserSidebarSelection.isCoveredBySelectedFolder(.tab($0.id), in: configuration.browser)
        }
    }

    private var groupTint: Color {
        configuration.isPresented ? CrestColor.hover : CrestColor.chromeSurface
    }

    private var containerShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: BrowserDeviceAppearanceStore.shared.containerCornerRadius(
                padding: configuration.metrics.containerPadding),
            style: .continuous
        )
    }

    private var surfaceAnimation: Animation? {
        BrowserVisualAccessibilityPolicy.animation(
            CrestMotion.surface,
            reduceMotion: reduceMotion
        )
    }
}
