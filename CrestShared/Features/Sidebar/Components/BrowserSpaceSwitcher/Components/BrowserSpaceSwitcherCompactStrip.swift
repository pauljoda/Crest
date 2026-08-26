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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

                picker(viewportWidth: allocation.pickerViewportWidth)
            }
        }
        .frame(height: BrowserSpaceSwitcherLayout.compactStripHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spaces")
    }

    private func picker(viewportWidth: CGFloat) -> some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
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
                .frame(minWidth: viewportWidth, alignment: .center)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(
                width: viewportWidth,
                height: BrowserSpaceSwitcherLayout.segmentHeight
                    + 2 * CrestSpaceIconPickerMetrics.trackPadding
            )
            .task(id: selectedSpaceID) {
                await Task.yield()
                revealSelection(reader, animated: true)
            }
            .onChange(of: viewportWidth) {
                revealSelection(reader, animated: false)
            }
            .onChange(of: BrowserSpaceSwitcherLayout.segmentIDs(for: spaces)) {
                revealSelection(reader, animated: false)
            }
            .accessibilitySortPriority(
                BrowserSpaceSwitcherLayout.pickerAccessibilityPriority
            )
        }
    }

    private func revealSelection(
        _ reader: ScrollViewProxy,
        animated: Bool
    ) {
        guard
            let target = BrowserSpaceSwitcherLayout.compactScrollTarget(
                spaceIDs: BrowserSpaceSwitcherLayout.segmentIDs(for: spaces),
                selectedSpaceID: selectedSpaceID
            )
        else { return }

        if animated {
            withAnimation(
                BrowserVisualAccessibilityPolicy.animation(
                    CrestMotion.scrollAlignment,
                    reduceMotion: reduceMotion
                )
            ) {
                reader.scrollTo(target, anchor: .center)
            }
        } else {
            reader.scrollTo(target, anchor: .center)
        }
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
