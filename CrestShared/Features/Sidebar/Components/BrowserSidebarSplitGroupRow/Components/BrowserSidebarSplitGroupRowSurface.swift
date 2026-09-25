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
                        if let tint = configuration.tint {
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

    private var isMultiSelected: Bool {
        configuration.members.contains {
            BrowserSidebarSelection.showsSelected(.tab($0.id), in: configuration.context)
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
