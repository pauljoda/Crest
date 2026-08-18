import SwiftUI

struct BrowserRootDockedSidebarLayer<Content: View>: View {
    let presentation: BrowserSidebarPresentation
    let width: CGFloat
    let reduceMotion: Bool
    let morphsWithFloatingSidebar: Bool
    let isApproachingDock: Bool
    let namespace: Namespace.ID
    let hoverChanged: (Bool) -> Void
    let content: Content

    init(
        presentation: BrowserSidebarPresentation,
        width: CGFloat,
        reduceMotion: Bool,
        morphsWithFloatingSidebar: Bool,
        isApproachingDock: Bool,
        namespace: Namespace.ID,
        hoverChanged: @escaping (Bool) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.presentation = presentation
        self.width = width
        self.reduceMotion = reduceMotion
        self.morphsWithFloatingSidebar = morphsWithFloatingSidebar
        self.isApproachingDock = isApproachingDock
        self.namespace = namespace
        self.hoverChanged = hoverChanged
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .leading) {
            if presentation == .docked {
                content
                    .frame(width: width)
                    .modifier(
                        BrowserDockedSidebarGeometryModifier(
                            isActive: morphsWithFloatingSidebar,
                            namespace: namespace
                        )
                    )
                    .onHover(perform: hoverChanged)
                    .transition(
                        morphsWithFloatingSidebar
                            ? .identity
                            : reduceMotion
                                ? .opacity
                                : .move(edge: .leading).combined(with: .opacity)
                    )
            }
        }
        // Keep one layout participant alive for the lifetime of the shell.
        // Animating its reservation lets the page edge travel with the sidebar
        // instead of inserting a full-width column before the surface morphs.
        .frame(
            width: presentation.reservedWidth(
                for: width,
                whileApproachingDock: isApproachingDock
            ),
            alignment: .leading
        )
    }
}

private struct BrowserDockedSidebarGeometryModifier: ViewModifier {
    let isActive: Bool
    let namespace: Namespace.ID

    @ViewBuilder
    func body(content: Content) -> some View {
        if isActive {
            content.matchedGeometryEffect(
                id: BrowserSidebarPresentationPolicy.matchedGeometryID,
                in: namespace,
                properties: .frame,
                anchor: .topLeading,
                isSource: true
            )
        } else {
            content
        }
    }
}
