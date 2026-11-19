import SwiftUI

struct MobileCompactPageSurface<Backdrop: View, Detail: View>: View {
    // MARK: - Static Variables

    /// Whether a downward swipe may dismiss the full-screen page.
    private static var allowsInteractiveDismissal: Bool { false }

    // MARK: - Variables

    let selectedTab: TabStateModel?
    /// The window's notices, which show over the page unless a sheet over it
    /// shows them instead.
    let notices: BrowserNotices
    let showsNotices: Bool
    let reduceMotion: Bool
    /// Whether the page rises over setup as setup hands over, where the tab
    /// it would grow from lies hidden under setup.
    let risesOverSetup: Bool
    let tabPromotionNamespace: Namespace.ID
    let completePagePresentation: () -> Void
    let backdrop: Backdrop
    let detail: Detail

    /// Whether this page rose over setup, kept as it was when the page came
    /// up, so the page stays the same view once setup goes from under it.
    @State private var roseOverSetup: Bool?

    @ViewBuilder
    var body: some View {
        let page = ZStack {
            backdrop
            detail
        }
        .interactiveDismissDisabled(
            !Self.allowsInteractiveDismissal
        )
        .onAppear {
            if roseOverSetup == nil { roseOverSetup = risesOverSetup }
            completePagePresentation()
        }
        .overlay(alignment: .top) {
            if showsNotices {
                BrowserNoticeLayer(
                    notices: notices,
                    alignment: .top,
                    topInset: MobileBrowserRootLayout.compactOverlayTopPadding,
                    sideInset: MobileBrowserRootLayout.displayEdgeMargin
                )
            }
        }
        // The page covers the window, so it carries its own side toolbar; the
        // zoom below stays on the presentation's outermost view.
        .modifier(MobileBrowserSideToolbarHost())

        if reduceMotion || (roseOverSetup ?? risesOverSetup) {
            page
        } else if let selectedTab,
            selectedTab.isPromotionSource(isSelected: true)
        {
            page.navigationTransition(
                .zoom(
                    sourceID: BrowserTabPromotionID.value(for: selectedTab.id),
                    in: tabPromotionNamespace
                )
            )
        } else {
            page
        }
    }
}
