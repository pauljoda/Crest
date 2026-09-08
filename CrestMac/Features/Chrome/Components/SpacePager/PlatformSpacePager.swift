import AppKit
import SwiftUI

/// SwiftUI supplies semantic state and content. AppKit owns only sidebar motion.
struct PlatformSpacePager<Content: View>: NSViewRepresentable {
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID
    let isInteractionLocked: Bool
    let selectSpace: (SpaceID) -> SpaceID
    let settledSpace: (SpaceID) -> Void
    @ViewBuilder let content: (BrowserSpace, Bool) -> Content

    func makeNSView(context: Context) -> SpacePagerViewport<Content> {
        SpacePagerViewport(frame: .zero)
    }

    func updateNSView(_ view: SpacePagerViewport<Content>, context: Context) {
        let environment = context.environment
        view.update(
            spaces: spaces, selectedSpaceID: selectedSpaceID,
            isInteractionLocked: isInteractionLocked,
            reduceMotion: environment.accessibilityReduceMotion,
            layoutDirection: environment.layoutDirection,
            selectSpace: selectSpace, settledSpace: settledSpace
        ) { space, isSelected in
            SpacePageRoot(
                content: content(space, isSelected), environment: environment,
                assignment: BrowserSpaceRuntimeAssignment(space: space))
        }
    }

    static func dismantleNSView(_ view: SpacePagerViewport<Content>, coordinator: ()) {
        view.teardown()
    }
}

/// A retained host preserves the supplied namespace, capabilities, and environment.
struct SpacePageRoot<Content: View>: View {
    let content: Content
    let environment: EnvironmentValues
    let assignment: BrowserSpaceRuntimeAssignment

    var body: some View {
        content
            .environment(\.self, environment)
            .id(assignment)
    }
}

@MainActor
final class SpacePageHost<Content: View>: NSView {
    let hostingView: NSHostingView<SpacePageRoot<Content>>

    init(root: SpacePageRoot<Content>) {
        hostingView = NSHostingView(rootView: root)
        super.init(frame: .zero)
        wantsLayer = true
        hostingView.sizingOptions = []
        hostingView.safeAreaRegions = []
        hostingView.autoresizingMask = [.width, .height]
        addSubview(hostingView)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { return nil }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
    }
}
