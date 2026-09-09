import AppKit
import SwiftUI

extension EnvironmentValues {
    @Entry var spacePagerContentTopInsets: [SpaceID: CGFloat] = [:]
}

/// SwiftUI supplies semantic state and content. AppKit owns only sidebar motion.
struct PlatformSpacePager<Content: View>: NSViewRepresentable {
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID
    let isInteractionLocked: Bool
    let selectSpace: (SpaceID) -> SpaceID
    @ViewBuilder let content: (BrowserSpace, Bool) -> Content

    func makeNSView(context: Context) -> SpacePagerViewport<Content> {
        SpacePagerViewport(frame: .zero)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: SpacePagerViewport<Content>, context: Context
    ) -> CGSize? {
        // The shell determines the viewport; retained pages fill that size.
        // Avoid native fitting traversing those page subtrees whenever their
        // scroll geometry changes.
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    func updateNSView(_ view: SpacePagerViewport<Content>, context: Context) {
        let environment = context.environment
        view.update(
            spaces: spaces, selectedSpaceID: selectedSpaceID,
            isInteractionLocked: isInteractionLocked,
            reduceMotion: environment.accessibilityReduceMotion,
            layoutDirection: environment.layoutDirection,
            presentation: environment.spacePagerPresentation,
            contentTopInsets: environment.spacePagerContentTopInsets,
            selectSpace: selectSpace
        ) { space, isSelected in
            SpacePageRoot(
                content: content(space, isSelected),
                assignment: BrowserSpaceRuntimeAssignment(space: space))
        }
    }

    static func dismantleNSView(_ view: SpacePagerViewport<Content>, coordinator: ()) {
        view.teardown()
    }
}
