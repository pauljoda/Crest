import SwiftUI

/// A centred, horizontally scrolling Space picker with the shell's accessories
/// held clear at either edge.
///
/// The picker gets an explicit viewport from the actual strip width and the
/// larger occupied utility side. Its segments keep their native size and
/// identity, so overflow scrolls and the active Space can always be revealed.
struct BrowserSpaceSwitcherCompactStrip: View {
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID
    let reorderState: BrowserSidebarReorderState
    let metrics: BrowserSpacePickerMetrics
    let selectSpace: (SpaceID) -> Void
    let accessories: BrowserSpaceSwitcherAccessories
    let downloads: BrowserSpaceSwitcherDownloads

    var body: some View {
        GeometryReader { geometry in
            let allocation = BrowserSpaceSwitcherLayout.compactStripAllocation(
                availableWidth: geometry.size.width,
                spaceCount: spaces.count,
                leadingUtilityWidth: accessories.sidebarToggle == nil
                    ? 0
                    : BrowserSpaceSwitcherLayout.utilityButtonSize,
                trailingUtilityWidth: accessories.commonLists == nil
                    ? 0
                    : BrowserSpaceSwitcherLayout.utilityButtonSize
            )

            ZStack {
                HStack(spacing: BrowserSpaceSwitcherLayout.compactStripSpacing) {
                    if let sidebarToggle = accessories.sidebarToggle {
                        toggleButton(sidebarToggle)
                    }

                    Spacer()

                    if let commonLists = accessories.commonLists {
                        commonListsButton(commonLists)
                    }
                }
                .padding(
                    .horizontal,
                    BrowserSpaceSwitcherLayout.compactStripHorizontalInset
                )

                BrowserSpaceSwitcherCompactPicker(
                    spaces: spaces,
                    selectedSpaceID: selectedSpaceID,
                    reorderState: reorderState,
                    metrics: metrics,
                    selectSpace: selectSpace,
                    allocation: allocation
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: BrowserSpaceSwitcherLayout.compactStripHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spaces")
    }

    private func toggleButton(
        _ sidebarToggle: BrowserSpaceSwitcherSidebarToggle
    ) -> some View {
        Button(
            sidebarToggle.action.title,
            systemImage: sidebarToggle.sidebarOnRight ? "sidebar.right" : "sidebar.left",
            action: sidebarToggle.toggle
        )
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .frame(
            width: BrowserSpaceSwitcherLayout.utilityButtonSize,
            height: BrowserSpaceSwitcherLayout.utilityButtonSize
        )
        .accessibilitySortPriority(
            BrowserSpaceSwitcherLayout.leadingUtilityAccessibilityPriority
        )
        .accessibilityIdentifier("browser-sidebar-toggle")
        .help(sidebarToggle.action.title)
    }

    private func commonListsButton(
        _ commonLists: BrowserSpaceSwitcherCommonLists
    ) -> some View {
        BrowserSpaceSwitcherCommonListsButton(
            isExpanded: commonLists.isExpanded,
            downloads: downloads.items,
            newDownloads: downloads.newItems,
            badgeColor: downloads.badgeColor,
            action: commonLists.toggle,
            recordFrame: commonLists.recordTriggerFrame
        )
        .accessibilitySortPriority(
            BrowserSpaceSwitcherLayout.trailingUtilityAccessibilityPriority
        )
    }
}
