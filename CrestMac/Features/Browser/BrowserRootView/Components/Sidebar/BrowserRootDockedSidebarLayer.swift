import SwiftUI

struct BrowserRootDockedSidebarLayer<Content: View>: View {
    let presentation: BrowserSidebarPresentation
    let width: CGFloat
    let reduceMotion: Bool
    let morphsWithFloatingSidebar: Bool
    let namespace: Namespace.ID
    let hoverChanged: (Bool) -> Void
    let content: Content

    init(
        presentation: BrowserSidebarPresentation,
        width: CGFloat,
        reduceMotion: Bool,
        morphsWithFloatingSidebar: Bool,
        namespace: Namespace.ID,
        hoverChanged: @escaping (Bool) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.presentation = presentation
        self.width = width
        self.reduceMotion = reduceMotion
        self.morphsWithFloatingSidebar = morphsWithFloatingSidebar
        self.namespace = namespace
        self.hoverChanged = hoverChanged
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
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
