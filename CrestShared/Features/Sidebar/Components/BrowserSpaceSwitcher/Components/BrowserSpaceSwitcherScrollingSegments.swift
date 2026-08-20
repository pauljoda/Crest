import SwiftUI

/// A horizontally scrolling segmented control that keeps the selected Space
/// centred.
///
/// Segments sized for a finger run out of room after a handful of Spaces, so
/// the track scrolls rather than shrinking them. A flick steps by whole
/// segments instead of scrolling freely, which is what makes the control land
/// on a Space rather than between two.
struct BrowserSpaceSwitcherScrollingSegments: View {
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID
    let reorderState: BrowserSidebarReorderState
    let metrics: BrowserSpacePickerMetrics
    let selectSpace: (SpaceID) -> Void

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollAnchorSpaceID: SpaceID?

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { reader in
                track(width: pickerWidth(for: geometry.size.width))
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .highPriorityGesture(stepGesture(reader))
                    .accessibilityLabel("Spaces")
                    .accessibilityIdentifier("space-switcher-picker")
                    .task(id: selectedSpaceID) {
                        await Task.yield()
                        scrollAnchorSpaceID = selectedSpaceID
                        centerSelection(reader, on: selectedSpaceID)
                    }
            }
        }
        .frame(height: BrowserSpaceSwitcherLayout.scrollingSegmentExtent)
        .padding(
            .horizontal,
            BrowserSpaceSwitcherLayout.scrollingTrackHorizontalInset
        )
        .padding(.top, BrowserSpaceSwitcherLayout.scrollingTrackTopInset)
    }

    private func track(width: CGFloat) -> some View {
        ScrollView(.horizontal) {
            ZStack {
                Picker("Spaces", selection: selection) {
                    ForEach(spaces) { space in
                        BrowserSpacePickerSegment(
                            space: space,
                            reorderState: reorderState,
                            metrics: metrics
                        )
                        .tag(space.id)
                        .accessibilityLabel(space.name)
                        .accessibilityValue(
                            space.accessPolicy.requiresAuthentication
                                ? "Private Space"
                                : "Open Space"
                        )
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.extraLarge)
                .labelsHidden()

                scrollAnchors(width: width)
            }
            .frame(
                width: width,
                height: BrowserSpaceSwitcherLayout.scrollingSegmentExtent
            )
        }
    }

    /// A flick is read as a step count rather than as a scroll offset, so the
    /// track always settles on a Space. The translation is turned semantic
    /// first, which is what keeps "flick left" meaning "the next Space" in a
    /// right-to-left layout.
    private func stepGesture(_ reader: ScrollViewProxy) -> some Gesture {
        DragGesture(
            minimumDistance: BrowserSpaceSwitcherLayout.scrollingStepThreshold
        )
        .onEnded { value in
            guard let destination = scrollDestination(for: value.translation.width)
            else { return }
            scrollAnchorSpaceID = destination
            centerSelection(reader, on: destination)
        }
    }

    private func centerSelection(_ reader: ScrollViewProxy, on spaceID: SpaceID) {
        withAnimation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.scrollAlignment,
                reduceMotion: reduceMotion
            )
        ) {
            reader.scrollTo(spaceID, anchor: .center)
        }
    }

    private var selection: Binding<SpaceID> {
        Binding(
            get: { selectedSpaceID },
            set: { spaceID in selectSpace(spaceID) }
        )
    }

    private func pickerWidth(for availableWidth: CGFloat) -> CGFloat {
        max(
            availableWidth,
            CGFloat(spaces.count)
                * BrowserSpaceSwitcherLayout.scrollingSegmentExtent
        )
    }

    /// The picker draws its own segments and will not hand out anchors, so an
    /// invisible row of equal slices carries the identities `scrollTo` needs.
    private func scrollAnchors(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(spaces) { space in
                Color.clear
                    .frame(width: width / CGFloat(max(spaces.count, 1)))
                    .id(space.id)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func scrollDestination(for translation: CGFloat) -> SpaceID? {
        let extent = BrowserSpaceSwitcherLayout.scrollingSegmentExtent
        guard !spaces.isEmpty,
            abs(translation)
                >= BrowserSpaceSwitcherLayout.scrollingStepThreshold,
            let currentIndex = spaces.firstIndex(where: {
                $0.id == (scrollAnchorSpaceID ?? selectedSpaceID)
            })
        else { return nil }

        let semanticTranslation =
            BrowserChromeDirectionPolicy.semanticHorizontalTranslation(
                translation,
                layoutDirection: layoutDirection
            )
        let stepCount = max(1, Int(ceil(abs(translation) / extent)))
        let requestedIndex =
            semanticTranslation < 0
            ? currentIndex + stepCount
            : currentIndex - stepCount
        let destinationIndex = min(
            max(requestedIndex, spaces.startIndex),
            spaces.index(before: spaces.endIndex)
        )
        return spaces[destinationIndex].id
    }
}
