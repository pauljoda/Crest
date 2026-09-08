import SwiftUI

/// Shared selection and accessibility contract; each input platform owns the
/// viewport motion without publishing a browsing-state change for every frame.
struct BrowserSpacePager<Content: View>: View {
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID
    var isInteractionLocked = false
    /// Returns the actual selection so a refused request cannot leave native
    /// presentation waiting for a state change that will never arrive.
    let selectSpace: (SpaceID) -> SpaceID
    var settledSpace: (SpaceID) -> Void = { _ in }
    @ViewBuilder let content: (BrowserSpace, Bool) -> Content

    var body: some View {
        PlatformSpacePager(
            spaces: spaces,
            selectedSpaceID: selectedSpaceID,
            isInteractionLocked: isInteractionLocked,
            selectSpace: selectSpace,
            settledSpace: settledSpace,
            content: content
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spaces")
        .accessibilityValue(
            BrowserChromeAccessibility.spaceValue(spaces: spaces, selectedSpaceID: selectedSpaceID)
        )
        .accessibilityIdentifier("space-pager")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: selectAdjacentSpace(.next)
            case .decrement: selectAdjacentSpace(.previous)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Previous Space") { selectAdjacentSpace(.previous) }
        .accessibilityAction(named: "Next Space") { selectAdjacentSpace(.next) }
    }

    private func selectAdjacentSpace(_ direction: BrowserSpaceSwipeDirection) {
        guard !isInteractionLocked,
            let spaceID = BrowserChromeAccessibility.adjacentSpaceID(
                spaces: spaces, selectedSpaceID: selectedSpaceID,
                direction: direction == .next ? .next : .previous)
        else { return }
        _ = selectSpace(spaceID)
    }
}
