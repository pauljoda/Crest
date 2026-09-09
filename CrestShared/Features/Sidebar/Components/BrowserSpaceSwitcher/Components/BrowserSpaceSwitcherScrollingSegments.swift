import SwiftUI

/// Touch keeps the capsule appearance, using the same progress-driven buttons
/// and clear overflow controls as the compact desktop lane.
struct BrowserSpaceSwitcherScrollingSegments: View {
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID
    let reorderState: BrowserSidebarReorderState
    let metrics: BrowserSpacePickerMetrics
    let selectSpace: (SpaceID) -> Void

    var body: some View {
        GeometryReader { geometry in
            let style = CrestSpaceIconPickerStyle.touch
            let allocation = BrowserSpaceSwitcherCompactAllocation(
                pickerViewportWidth: geometry.size.width,
                pickerContentWidth: CGFloat(spaces.count) * style.minimumSegmentWidth
                    + 2 * CrestSpaceIconPickerMetrics.trackPadding,
                overflowButtonWidth: style.overflowButtonWidth)
            BrowserSpaceSwitcherCompactPicker(
                spaces: spaces, selectedSpaceID: selectedSpaceID,
                reorderState: reorderState, metrics: metrics, selectSpace: selectSpace,
                allocation: allocation, style: style)
        }
        .frame(height: CrestSpaceIconPickerStyle.touch.height)
        .padding(.horizontal, BrowserSpaceSwitcherLayout.scrollingTrackHorizontalInset)
        .padding(.top, BrowserSpaceSwitcherLayout.scrollingTrackTopInset)
    }
}
