import SwiftUI

struct MobileCompactBrowserSurface<
    DockedSidebar: View,
    FloatingSidebar: View,
    Page: View
>: View {
    let compactShowsPage: Bool
    @Binding var isPagePresented: Bool
    let usesDockedDetailPresentation: Bool
    let sidebarPresentation: BrowserSidebarPresentation
    @Binding var preferredSidebarWidth: CGFloat
    let space: BrowserSpace?
    let reduceTransparency: Bool
    let layoutDirection: LayoutDirection
    let usesBorderlessFloatingPageFrame: Bool
    let isStartPage: Bool
    let hasActivePage: Bool
    let hasSelectedSpace: Bool
    let showSidebar: () -> Void
    let commitSidebarWidth: (CGFloat) -> Void
    let dockedSidebar: DockedSidebar
    let floatingSidebar: FloatingSidebar
    let page: Page

    var body: some View {
        dockedSidebar
            .allowsHitTesting(!compactShowsPage)
            .accessibilityHidden(compactShowsPage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .fullScreenCover(isPresented: $isPagePresented) {
                if usesDockedDetailPresentation {
                    // Preserve the original phone tab-to-detail composition.
                    // Its backdrop owns the safe-area tint and its detail owns
                    // the floating URL controls.
                    page
                } else {
                    ZStack {
                        BrowserWindowAtmosphere(space: space)
                            .ignoresSafeArea()

                        GeometryReader { proxy in
                            MobileRegularBrowserLayout(
                                layout: MobileRegularWindowLayoutPolicy.resolve(
                                    availableWidth: proxy.size.width,
                                    preferredSidebarWidth: preferredSidebarWidth
                                ),
                                sidebarPresentation: sidebarPresentation,
                                preferredSidebarWidth: $preferredSidebarWidth,
                                reduceTransparency: reduceTransparency,
                                layoutDirection: layoutDirection,
                                space: space,
                                showSidebar: showSidebar,
                                commitSidebarWidth: commitSidebarWidth,
                                sidebar: floatingSidebar,
                                detail: floatingDetail
                            )
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private var floatingDetail: some View {
        if usesBorderlessFloatingPageFrame {
            page
        } else {
            BrowserRootDetailSurface(
                adjoinsLeadingSidebar: false,
                usesBorderlessFrame: false,
                isStartPage: isStartPage,
                hasActivePage: hasActivePage,
                hasSelectedSpace: hasSelectedSpace,
                handleWebContentInteraction: {},
                content: page
            )
        }
    }
}
