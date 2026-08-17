import SwiftUI

struct BrowserRootFloatingSidebarLayer<Content: View>: View {
    let presentation: BrowserSidebarPresentation
    let width: CGFloat
    let space: BrowserSpace?
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let hoverChanged: (Bool) -> Void
    let content: Content

    init(
        presentation: BrowserSidebarPresentation,
        width: CGFloat,
        space: BrowserSpace?,
        reduceMotion: Bool,
        reduceTransparency: Bool,
        hoverChanged: @escaping (Bool) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.presentation = presentation
        self.width = width
        self.space = space
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.hoverChanged = hoverChanged
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if presentation == .floating {
            let shape = RoundedRectangle(
                cornerRadius: BrowserSidebarPresentationPolicy
                    .floatingCardCornerRadius,
                style: .continuous
            )

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
                            lineWidth: BrowserRootMetrics
                                .floatingSidebarBorderWidth
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
                .padding(BrowserSidebarPresentationPolicy.floatingCardInset)
                .frame(
                    width: BrowserSidebarPresentationPolicy
                        .floatingHoverRegionWidth(sidebarWidth: width)
                )
                .frame(maxHeight: .infinity)
                .contentShape(.interaction, .rect)
                .onHover(perform: hoverChanged)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .leading).combined(with: .opacity)
                )
                .zIndex(BrowserRootMetrics.floatingSidebarZIndex)
        }
    }
}
