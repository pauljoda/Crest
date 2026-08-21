import SwiftUI

/// The regular-width mobile shell uses the same sidebar surface and reservation
/// components as macOS. Mobile owns only the touch reveal control and the
/// narrow-window decision that a docked sidebar cannot consume an unusable page.
struct MobileRegularBrowserLayout<Sidebar: View, Detail: View>: View,
    BrowserChromeAnimating
{
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    let layout: MobileRegularWindowLayout
    let sidebarPresentation: BrowserSidebarPresentation
    @Binding var preferredSidebarWidth: CGFloat
    let reduceTransparency: Bool
    let layoutDirection: LayoutDirection
    let space: BrowserSpace?
    let showSidebar: () -> Void
    let commitSidebarWidth: (CGFloat) -> Void
    let sidebar: Sidebar
    let detail: Detail

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                BrowserRootSidebarLayoutReservation(
                    presentation: effectivePresentation,
                    width: layout.sidebarWidth,
                    isApproachingDock: false
                )

                detail
            }

            BrowserRootSidebarSurfaceLayer(
                presentation: effectivePresentation,
                width: layout.sidebarWidth,
                space: space,
                reduceTransparency: reduceTransparency,
                hoverChanged: { _ in }
            ) {
                sidebar
            }

            if effectivePresentation == .collapsed {
                BrowserCollapsedSidebarRevealControl(
                    capabilities: BrowserInteractionCapabilities(
                        supportsTouch: true
                    ),
                    showSidebar: showSidebar
                )
                .zIndex(BrowserRootMetrics.floatingSidebarZIndex)
            } else if effectivePresentation == .docked {
                BrowserSidebarResizeHandle(
                    width: $preferredSidebarWidth,
                    onResizeEnded: commitSidebarWidth
                )
                .offset(
                    x: BrowserChromeDirectionPolicy.leadingOffset(
                        layout.sidebarWidth
                            - MobileBrowserRootLayout.resizeHandleOverlap,
                        layoutDirection: layoutDirection
                    )
                )
                .zIndex(BrowserRootMetrics.sidebarResizeControlZIndex)
            }
        }
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
