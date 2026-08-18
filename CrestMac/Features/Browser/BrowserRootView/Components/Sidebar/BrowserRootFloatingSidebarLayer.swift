import SwiftUI

struct BrowserRootFloatingSidebarLayer<Content: View>: View {
    let presentation: BrowserSidebarPresentation
    let width: CGFloat
    let space: BrowserSpace?
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let morphsWithDockedSidebar: Bool
    let namespace: Namespace.ID
    let hoverChanged: (Bool) -> Void
    let content: Content

    init(
        presentation: BrowserSidebarPresentation,
        width: CGFloat,
        space: BrowserSpace?,
        reduceMotion: Bool,
        reduceTransparency: Bool,
        morphsWithDockedSidebar: Bool,
        namespace: Namespace.ID,
        hoverChanged: @escaping (Bool) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.presentation = presentation
        self.width = width
        self.space = space
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.morphsWithDockedSidebar = morphsWithDockedSidebar
        self.namespace = namespace
        self.hoverChanged = hoverChanged
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if presentation == .floating {
            cardSurface
                .modifier(
                    BrowserFloatingSidebarGeometryModifier(
                        isActive: morphsWithDockedSidebar,
                        namespace: namespace
                    )
                )
                .padding(BrowserSidebarPresentationPolicy.floatingCardInset)
                .frame(
                    width:
                        BrowserSidebarPresentationPolicy
                        .floatingHoverRegionWidth(sidebarWidth: width)
                )
                .frame(maxHeight: .infinity)
                .contentShape(.interaction, .rect)
                .onHover(perform: hoverChanged)
                .transition(
                    morphsWithDockedSidebar
                        ? .identity
                        : reduceMotion
                            ? .opacity
                            : .move(edge: .leading).combined(with: .opacity)
                )
                .zIndex(BrowserRootMetrics.floatingSidebarZIndex)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: BrowserSidebarPresentationPolicy
                .floatingCardCornerRadius,
            style: .continuous
        )
    }

    private var cardSurface: some View {
        content
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background {
                BrowserFloatingSidebarCardBackground(space: space)
            }
            .compositingGroup()
            .clipShape(shape)
            .overlay {
                shape
                    .strokeBorder(
                        .primary.opacity(
                            BrowserRootMetrics.floatingSidebarBorderOpacity
                        ),
                        lineWidth: BrowserRootMetrics.floatingSidebarBorderWidth
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(
                    reduceTransparency
                        ? 0
                        : BrowserRootMetrics.floatingSidebarShadowOpacity
                ),
                radius: BrowserRootMetrics.floatingSidebarShadowRadius,
                x: BrowserRootMetrics.floatingSidebarShadowOffset,
                y: BrowserRootMetrics.floatingSidebarShadowOffset
            )
            .contentShape(.interaction, shape)
    }
}

private struct BrowserFloatingSidebarGeometryModifier: ViewModifier {
    let isActive: Bool
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        // Changing only the source role preserves the sidebar's structural
        // identity while still giving the docked surface ownership during a
        // morph. An inactive floating surface owns itself and needs no peer.
        content.matchedGeometryEffect(
            id: BrowserSidebarPresentationPolicy.matchedGeometryID,
            in: namespace,
            properties: .frame,
            anchor: .topLeading,
            isSource: BrowserSidebarPresentation.floating
                .isMatchedGeometrySource(whileMorphing: isActive)
        )
    }
}
