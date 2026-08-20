import SwiftUI

/// The grouped container a split's tab rows sit in: one surface, one drag
/// source, one set of drop anchors, and one context menu for the whole run.
struct BrowserSidebarSplitGroupRowSurface: ViewModifier {
    let configuration: BrowserSidebarSplitGroupRowConfiguration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .background(groupTint, in: containerShape)
            .animation(surfaceAnimation, value: configuration.isPresented)
            .padding(.horizontal, configuration.rowHorizontalInset)
            .padding(.vertical, configuration.metrics.rowVerticalInset)
            .contentShape(.rect)
            // Registers the whole group as one reorder row and arms its lift.
            // The registration is also what makes a tab dragged past the group
            // step over the run as a single slot instead of landing between two
            // members. `members` is only the run a shell that draws its own
            // lift preview builds it from; a shell that lifts the row itself
            // ignores it.
            .browserSplitGroupDraggable(
                item: configuration.dragItem,
                members: configuration.members,
                placement: configuration.placement,
                folderID: configuration.folderID,
                reorder: configuration.reorderContext,
                isEnabled: configuration.isCurrentAndUnlocked
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
            .contextMenu {
                BrowserSidebarSplitGroupContextMenu(
                    configuration: configuration
                )
                .tint(.primary)
            }
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
    private var groupTint: Color {
        configuration.isPresented ? CrestColor.hover : CrestColor.chromeSurface
    }

    private var containerShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: configuration.metrics.containerCornerRadius,
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
