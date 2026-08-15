import SwiftUI

struct MobileRegularOverlayLayout<Sidebar: View, Detail: View>: View {
    let sidebarWidth: CGFloat
    let sidebarIsPresented: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let layoutDirection: LayoutDirection
    let showSidebar: () -> Void
    let hideSidebar: () -> Void
    let sidebar: Sidebar
    let detail: Detail

    var body: some View {
        ZStack(alignment: .leading) {
            detail

            if sidebarIsPresented {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: sidebarWidth)

                    Color.black.opacity(
                        BrowserVisualAccessibilityPolicy.scrimOpacity(
                            MobileBrowserRootLayout.overlayScrimOpacity,
                            reduceTransparency: reduceTransparency
                        )
                    )
                }
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture {
                    hideSidebar()
                }
                .accessibilityHidden(true)

                sidebar
                    .frame(width: sidebarWidth)
                    .shadow(
                        color: .black.opacity(
                            reduceTransparency
                                ? 0
                                : MobileBrowserRootLayout.overlayShadowOpacity
                        ),
                        radius: MobileBrowserRootLayout.overlayShadowRadius,
                        x: BrowserChromeDirectionPolicy.leadingOffset(
                            MobileBrowserRootLayout.overlayShadowOffset,
                            layoutDirection: layoutDirection
                        )
                    )
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .leading).combined(with: .opacity)
                    )
                    .zIndex(MobileBrowserRootLayout.sidebarLayer)
            } else {
                MobileCollapsedSidebarRevealControl(showSidebar: showSidebar)
                    .zIndex(MobileBrowserRootLayout.sidebarLayer)
            }
        }
    }
}

#Preview("Mobile Regular Overlay") {
    MobileRegularOverlayLayout(
        sidebarWidth: 320,
        sidebarIsPresented: true,
        reduceMotion: false,
        reduceTransparency: false,
        layoutDirection: .leftToRight,
        showSidebar: {},
        hideSidebar: {},
        sidebar: Color.indigo.opacity(0.2),
        detail: Color(uiColor: .systemBackground)
    )
}
