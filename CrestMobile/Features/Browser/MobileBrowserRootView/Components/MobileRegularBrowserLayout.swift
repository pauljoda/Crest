import SwiftUI

/// The regular-width mobile shell uses the same sidebar surface and reservation
/// components as macOS. Mobile owns only the touch reveal control and the
/// narrow-window decision that a docked sidebar cannot consume an unusable page.
struct MobileRegularBrowserLayout<Sidebar: View, Detail: View>: View,
    BrowserChromeAnimating
{
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.browserChromeAppearance) private var appearance

    private var sidebarEdge: HorizontalEdge { appearance.sidebarEdge(in: layoutDirection) }

    let layout: MobileRegularWindowLayout
    let sidebarPresentation: BrowserSidebarPresentation
    @Binding var preferredSidebarWidth: CGFloat
    let reduceTransparency: Bool
    let layoutDirection: LayoutDirection
    let space: BrowserSpace?
    var spaces: [BrowserSpace] = []
    let showSidebar: () -> Void
    let commitSidebarWidth: (CGFloat) -> Void
    let sidebar: Sidebar
    let detail: Detail

    var body: some View {
        BrowserSidebarPageLayout(
            presentation: effectivePresentation, width: layout.sidebarWidth, edge: sidebarEdge
        ) {
            detail
                // Extend only the page; sidebar controls keep their safe-area placement.
                .ignoresSafeArea(.container, edges: appearance.borderless ? .bottom : [])
        } sidebar: {
            BrowserRootSidebarSurfaceLayer(
                presentation: effectivePresentation,
                width: layout.sidebarWidth,
                edge: sidebarEdge,
                space: space,
                reduceTransparency: reduceTransparency,
                spaces: spaces,
                hoverChanged: { _ in }
            ) {
                sidebar
            }

        } controls: {
            if effectivePresentation == .collapsed {
                BrowserCollapsedSidebarRevealControl(
                    capabilities: BrowserInteractionCapabilities(
                        supportsTouch: true
                    ),
                    showSidebar: showSidebar, edge: sidebarEdge
                )
                .zIndex(BrowserRootMetrics.floatingSidebarZIndex)
            } else if effectivePresentation == .docked {
                BrowserSidebarResizeHandle(
                    width: $preferredSidebarWidth,
                    onResizeEnded: commitSidebarWidth, edge: sidebarEdge
                )
                .offset(
                    x: BrowserChromeDirectionPolicy.leadingOffset(
                        (layout.sidebarWidth - MobileBrowserRootLayout.resizeHandleOverlap)
                            * (sidebarEdge == .leading ? 1 : -1),
                        layoutDirection: layoutDirection
                    )
                )
                .zIndex(BrowserRootMetrics.sidebarResizeControlZIndex)
            }
        }
        .animation(chromeAnimation(CrestMotion.collection), value: appearance.sidebarOnRight)
        .animation(
            chromeAnimation(
                effectivePresentation == .docked
                    ? CrestMotion.sidebarDockAttachment
                    : CrestMotion.sidebarMorph
            ),
            value: effectivePresentation
        )
    }

    /// Compact regular windows retain the desktop floating-card treatment, but
    /// do not reserve a sidebar width that would make the page unusable.
    private var effectivePresentation: BrowserSidebarPresentation {
        guard !layout.reservesSidebarWidth,
            sidebarPresentation != .collapsed
        else { return sidebarPresentation }
        return .floating
    }
}
