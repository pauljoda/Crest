import SwiftUI

struct BrowserRootSidebarSurfaceLayer<Content: View>: View {
    let presentation: BrowserSidebarPresentation
    let width: CGFloat
    let space: BrowserSpace?
    let reduceTransparency: Bool
    let hoverChanged: (Bool) -> Void
    let content: Content

    @Environment(\.layoutDirection) private var layoutDirection

    init(
        presentation: BrowserSidebarPresentation,
        width: CGFloat,
        space: BrowserSpace?,
        reduceTransparency: Bool,
        hoverChanged: @escaping (Bool) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.presentation = presentation
        self.width = width
        self.space = space
        self.reduceTransparency = reduceTransparency
        self.hoverChanged = hoverChanged
        self.content = content()
    }

    var body: some View {
        cardSurface
            .padding(surfaceInset)
            .frame(width: surfaceRegionWidth)
            .frame(maxHeight: .infinity)
            .contentShape(.interaction, .rect)
            .onHover(perform: hoverChanged)
            .offset(x: hiddenOffset)
            .opacity(presentation.showsSidebar ? 1 : 0)
            .allowsHitTesting(presentation.showsSidebar)
            .accessibilityHidden(!presentation.showsSidebar)
            .zIndex(
                presentation == .floating
                    ? BrowserRootMetrics.floatingSidebarZIndex
                    : 0
            )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: surfaceCornerRadius,
            style: .continuous
        )
    }

    private var cardSurface: some View {
        content
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .background {
                BrowserFloatingSidebarCardBackground(space: space)
                    .opacity(usesFloatingCardAppearance ? 1 : 0)
            }
            .compositingGroup()
            .clipShape(shape)
            .overlay {
                shape
                    .strokeBorder(
                        .primary.opacity(
                            usesFloatingCardAppearance
                                ? BrowserRootMetrics
                                    .floatingSidebarBorderOpacity
                                : 0
                        ),
                        lineWidth: BrowserRootMetrics.floatingSidebarBorderWidth
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(
                    reduceTransparency || !usesFloatingCardAppearance
                        ? 0
                        : BrowserRootMetrics.floatingSidebarShadowOpacity
                ),
                radius: BrowserRootMetrics.floatingSidebarShadowRadius,
                x: BrowserRootMetrics.floatingSidebarShadowOffset,
                y: BrowserRootMetrics.floatingSidebarShadowOffset
            )
            .contentShape(.interaction, shape)
    }

    private var usesFloatingCardAppearance: Bool {
        presentation != .docked
    }

    private var surfaceInset: CGFloat {
        usesFloatingCardAppearance
            ? BrowserSidebarPresentationPolicy.floatingCardInset
            : 0
    }

    private var surfaceCornerRadius: CGFloat {
        usesFloatingCardAppearance
            ? BrowserSidebarPresentationPolicy.floatingCardCornerRadius
            : 0
    }

    private var surfaceRegionWidth: CGFloat {
        usesFloatingCardAppearance
            ? BrowserSidebarPresentationPolicy.floatingHoverRegionWidth(
                sidebarWidth: width
            )
            : width
    }

    private var hiddenOffset: CGFloat {
        guard presentation == .collapsed else { return 0 }
        return BrowserChromeDirectionPolicy.leadingOffset(
            -surfaceRegionWidth,
            layoutDirection: layoutDirection
        )
    }
}
