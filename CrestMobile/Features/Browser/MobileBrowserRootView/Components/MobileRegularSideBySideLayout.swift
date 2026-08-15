import SwiftUI

struct MobileRegularSideBySideLayout<Sidebar: View, Detail: View>: View {
    let sidebarWidth: CGFloat
    let sidebarIsPresented: Bool
    @Binding var preferredSidebarWidth: CGFloat
    let reduceMotion: Bool
    let layoutDirection: LayoutDirection
    let showSidebar: () -> Void
    let commitSidebarWidth: (CGFloat) -> Void
    let sidebar: Sidebar
    let detail: Detail

    var body: some View {
        HStack(spacing: 0) {
            if sidebarIsPresented {
                sidebar
                    .frame(width: sidebarWidth)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .leading).combined(with: .opacity)
                    )
            }

            detail
        }
        .overlay(alignment: .leading) {
            if !sidebarIsPresented {
                MobileCollapsedSidebarRevealControl(showSidebar: showSidebar)
                    .zIndex(MobileBrowserRootLayout.sidebarLayer)
            } else {
                BrowserSidebarResizeHandle(
                    width: $preferredSidebarWidth,
                    onResizeEnded: commitSidebarWidth
                )
                .offset(
                    x: BrowserChromeDirectionPolicy.leadingOffset(
                        sidebarWidth - MobileBrowserRootLayout.resizeHandleOverlap,
                        layoutDirection: layoutDirection
                    )
                )
                .zIndex(MobileBrowserRootLayout.sidebarLayer)
            }
        }
    }
}

#Preview("Mobile Regular Side by Side") {
    @Previewable @State var sidebarWidth: CGFloat = 320
    MobileRegularSideBySideLayout(
        sidebarWidth: 320,
        sidebarIsPresented: true,
        preferredSidebarWidth: $sidebarWidth,
        reduceMotion: false,
        layoutDirection: .leftToRight,
        showSidebar: {},
        commitSidebarWidth: { _ in },
        sidebar: Color.indigo.opacity(0.2),
        detail: Color(uiColor: .systemBackground)
    )
}
