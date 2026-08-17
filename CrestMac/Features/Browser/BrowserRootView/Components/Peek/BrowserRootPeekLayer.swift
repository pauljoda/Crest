import SwiftUI

struct BrowserRootPeekLayer: View {
    let model: BrowserRootModel
    let transientBrowsing: BrowserTransientBrowsingCoordinator

    @Environment(\.layoutDirection) private var layoutDirection

    @ViewBuilder
    var body: some View {
        if let request = transientBrowsing.peekRequest {
            BrowserPeekOverlay(
                request: request,
                browser: model.browser,
                pages: model.pages,
                coordinator: transientBrowsing,
                reservedLeadingWidth:
                    model.sidebarPresentation.reservesSidebarWidth
                    ? model.sidebarWidth
                    : 0,
                layoutDirection: layoutDirection,
                spaceAccess: model.spaceAccess
            )
            .id(request.id)
            .zIndex(BrowserRootMetrics.peekZIndex)
        }
    }
}
