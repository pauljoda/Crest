import SwiftUI

/// A committed web page, rendered the one way Crest renders web pages on this
/// platform.
///
/// Every mobile surface that shows live web content goes through here: the
/// selected tab in `MobileBrowserDetailView`, each cell of the iPhone split
/// carousel, and each iPad split column. They differ in the
/// `MobileBrowserPageViewport` they are handed and in whether a tap asks for
/// focus — never in the treatment of the page itself. A grouped tab and a plain
/// tab therefore render identically by construction rather than by two places
/// agreeing to.
///
/// The safe-area treatment belongs here rather than at each call site because
/// it is part of that treatment: a page told to obscure the system safe areas
/// must also be laid out through them, and separating the two is exactly how a
/// surface ends up drawing a page behind the status bar.
struct MobileBrowserLivePageView: View {
    let page: MobileBrowserPage
    let viewport: MobileBrowserPageViewport
    var handleInteraction: (() -> Void)?
    /// An unfocused card's request to become the focused one. `nil` wherever
    /// the page on screen is already the focused one.
    var requestFocus: (() -> Void)?

    var body: some View {
        MobileBrowserWebView(
            page: page,
            viewport: viewport,
            handleInteraction: handleInteraction,
            requestFocus: requestFocus
        )
        .id(page.tabID)
        .opacity(
            BrowserPageSurfacePolicy.revealsWebContent(
                completedNavigationCount: page.completedNavigationCount
            ) ? 1 : 0
        )
        .background(
            Color(
                uiColor: BrowserPageSurfacePolicy.revealsWebContent(
                    completedNavigationCount: page.completedNavigationCount
                )
                    ? page.themeColor
                        ?? page.webView.underPageBackgroundColor
                        ?? .systemBackground
                    : .clear
            )
        )
        .ignoresSafeArea(
            .container,
            edges: viewport.obscuresSystemSafeAreas ? .vertical : []
        )
    }
}
