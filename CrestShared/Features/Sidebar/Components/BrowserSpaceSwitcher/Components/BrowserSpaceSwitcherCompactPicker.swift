import SwiftUI

/// A stable-height scroll lane with explicit controls for mouse-only scrolling.
struct BrowserSpaceSwitcherCompactPicker: View {
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID
    let reorderState: BrowserSidebarReorderState
    let metrics: BrowserSpacePickerMetrics
    let selectSpace: (SpaceID) -> Void
    let allocation: BrowserSpaceSwitcherCompactAllocation

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var overflow = BrowserSpacePickerOverflow()

    var body: some View {
        ScrollViewReader { reader in
            HStack(spacing: 0) {
                if allocation.usesOverflow {
                    overflowButton(forward: false, reader: reader)
                }
                track
                if allocation.usesOverflow {
                    overflowButton(forward: true, reader: reader)
                }
            }
            .frame(width: allocation.pickerViewportWidth)
            .task(id: selectedSpaceID) {
                await Task.yield()
                revealSelection(reader, animated: true)
            }
            .onChange(of: allocation.pickerViewportWidth) {
                revealSelection(reader, animated: false)
            }
            .onChange(of: BrowserSpaceSwitcherLayout.segmentIDs(for: spaces)) {
                revealSelection(reader, animated: false)
            }
        }
        .accessibilitySortPriority(BrowserSpaceSwitcherLayout.pickerAccessibilityPriority)
    }

    private var track: some View {
        ScrollView(.horizontal) {
            CrestSpaceIconPicker(
                spaces: spaces,
                selectedSpaceID: selectedSpaceID,
                selectSpace: selectSpace,
                accessibilityIdentifier: "space-switcher-picker"
            ) { space in
                BrowserSpacePickerSegment(
                    space: space, reorderState: reorderState, metrics: metrics
                )
            }
            .frame(minWidth: allocation.scrollViewportWidth, alignment: .center)
        }
        // `.hidden` still reserves a legacy scrollbar on macOS. The flanking
        // buttons provide scrolling without requiring a horizontal gesture.
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .frame(width: allocation.scrollViewportWidth, height: BrowserSpaceSwitcherLayout.pickerHeight)
        .clipShape(.rect(cornerRadius: BrowserSpaceSwitcherLayout.cornerRadius))
        .onScrollGeometryChange(for: BrowserSpacePickerOverflow.self) { geometry in
            BrowserSpacePickerOverflow(
                visibleRect: geometry.visibleRect,
                contentWidth: geometry.contentSize.width,
                spaceCount: spaces.count
            )
        } action: { _, value in
            overflow = value
        }
    }

    private func overflowButton(forward: Bool, reader: ScrollViewProxy) -> some View {
        let targetIndex = forward ? overflow.nextIndex : overflow.previousIndex
        let title: LocalizedStringResource = forward ? "Show Next Spaces" : "Show Previous Spaces"
        return Button {
            guard let targetIndex, spaces.indices.contains(targetIndex) else { return }
            withAnimation(scrollAnimation) {
                reader.scrollTo(spaces[targetIndex].id, anchor: forward ? .leading : .trailing)
            }
        } label: {
            Image(systemName: forward ? "chevron.forward" : "chevron.backward")
                .font(.caption.weight(.semibold))
                .frame(
                    width: BrowserSpaceSwitcherLayout.overflowButtonWidth,
                    height: BrowserSpaceSwitcherLayout.pickerHeight
                )
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .disabled(targetIndex == nil)
        .accessibilityLabel(Text(title))
        .help(Text(title))
        .accessibilityIdentifier(forward ? "space-picker-next" : "space-picker-previous")
    }

    private var scrollAnimation: Animation? {
        BrowserVisualAccessibilityPolicy.animation(CrestMotion.scrollAlignment, reduceMotion: reduceMotion)
    }

    private func revealSelection(_ reader: ScrollViewProxy, animated: Bool) {
        guard
            let target = BrowserSpaceSwitcherLayout.compactScrollTarget(
                spaceIDs: BrowserSpaceSwitcherLayout.segmentIDs(for: spaces),
                selectedSpaceID: selectedSpaceID
            )
        else { return }
        withAnimation(animated ? scrollAnimation : nil) {
            reader.scrollTo(target, anchor: .center)
        }
    }
}
