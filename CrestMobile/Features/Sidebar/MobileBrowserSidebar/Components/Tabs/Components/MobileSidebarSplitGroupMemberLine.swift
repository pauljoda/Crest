import SwiftUI

/// One member of a stacked split-group row: the tab row's own activation label
/// and close control at the tab row's own 44pt touch target, inset inside the
/// group's container.
///
/// The line is not a drag source. While tabs are grouped the group moves as a
/// unit, so a member can only leave through its close control or the menu.
struct MobileSidebarSplitGroupMemberLine: View {
    let configuration: MobileSidebarSplitGroupRowConfiguration
    let member: BrowserTab

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: MobileSidebarSplitGroupRowMetrics.memberContentSpacing) {
            MobileSidebarTabActivationButton(
                tab: member,
                profileID: configuration.profileID,
                isSelected: configuration.isFocused(member),
                isLoaded: configuration.isLoaded(member.id),
                restoreSavedLocation: nil,
                select: { configuration.activate(member) }
            )

            if configuration.canClose {
                closeButton
            }
        }
        .padding(
            .leading,
            MobileSidebarSplitGroupRowMetrics.memberLeadingInset
        )
        .padding(
            .trailing,
            MobileSidebarSplitGroupRowMetrics.memberTrailingInset
        )
        .frame(minHeight: lineHeight)
        .crestInteractiveSurface(
            isSelected: configuration.isFocused(member),
            isHovering: false,
            cornerRadius: MobileSidebarSplitGroupRowMetrics.memberCornerRadius
        )
        // Each member keeps its own anchor: the zoom into the page is driven by
        // the focused member, and a group whose lines shared one anchor would
        // zoom from the wrong place — or from nowhere at all.
        .mobileTabTransitionSource(
            id: MobileTabPromotionPolicy.destinationID(for: member.id),
            in: configuration.promotionNamespace,
            usesNativeNavigationTransition:
                configuration.usesNativeNavigationTransition,
            isEnabled: MobileTabPromotionPolicy.isTransitionSource(
                member,
                selectedTabID: configuration.selectedTabID
            )
        )
        .accessibilityElement(children: .contain)
        .contextMenu {
            MobileSidebarSplitGroupMemberContextMenu(
                configuration: configuration,
                member: member
            )
            .tint(.primary)
        }
    }

    private var closeButton: some View {
        Button("Close \(member.displayTitle)", systemImage: "xmark") {
            configuration.close(member)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .font(
            .system(
                size: MobileSidebarSplitGroupRowMetrics.closeGlyphSize,
                weight: .medium
            )
        )
        .frame(
            width: MobileSidebarSplitGroupRowMetrics.closeControlSize.width,
            height: MobileSidebarSplitGroupRowMetrics.closeControlSize.height
        )
        .foregroundStyle(BrowserVisualAccessibilityPolicy.tabCloseForeground)
        .opacity(configuration.isFocused(member) ? 1 : 0.65)
    }

    private var lineHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? MobileSidebarSplitGroupRowMetrics.accessibilityMemberLineHeight
            : MobileSidebarSplitGroupRowMetrics.memberLineHeight
    }
}

#Preview("Mobile Split Member Line", traits: .sizeThatFitsLayout) {
    let configuration = MobileSidebarSplitGroupRowPreviewFixture.configuration()

    MobileSidebarSplitGroupMemberLine(
        configuration: configuration,
        member: configuration.members[1]
    )
    .frame(width: 340)
    .padding()
}
