import SwiftUI

/// Every Space on screen at once, centred in a strip with the shell's
/// accessories pushed out to either edge.
///
/// The picker is centred by stacking rather than by spacers, so it stays in
/// the middle of the sidebar whether or not the accessories are there and
/// whichever widths they take.
struct BrowserSpaceSwitcherCompactStrip: View {
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID
    let reorderState: BrowserSidebarReorderState
    let metrics: BrowserSpacePickerMetrics
    let selectSpace: (SpaceID) -> Void
    let accessories: BrowserSpaceSwitcherAccessories
    let downloads: BrowserSpaceSwitcherDownloads

    var body: some View {
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

            CrestSpaceIconPicker(
                spaces: spaces,
                selectedSpaceID: selectedSpaceID,
                selectSpace: selectSpace,
                accessibilityIdentifier: "space-switcher-picker"
            ) { space in
                BrowserSpacePickerSegment(
                    space: space,
                    reorderState: reorderState,
                    metrics: metrics
                )
            }
        }
        .padding(
            .horizontal,
            BrowserSpaceSwitcherLayout.compactStripHorizontalInset
        )
        .frame(height: BrowserSpaceSwitcherLayout.compactStripHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spaces")
    }

    private func toggleButton(
        _ sidebarToggle: BrowserSpaceSwitcherSidebarToggle
    ) -> some View {
        Button(
            sidebarToggle.action.title,
            systemImage: "sidebar.left",
            action: sidebarToggle.toggle
        )
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .frame(
            width: BrowserSpaceSwitcherLayout.utilityButtonSize,
            height: BrowserSpaceSwitcherLayout.utilityButtonSize
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
    }
}
