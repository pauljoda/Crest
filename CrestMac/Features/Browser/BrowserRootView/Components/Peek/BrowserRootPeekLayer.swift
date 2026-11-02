import SwiftUI

struct BrowserRootPeekLayer: View {
    let model: BrowserRootModel
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let space: SpaceModel
    /// Whether the pages meet a docked sidebar, which leaves no frame on that
    /// edge.
    let docked: Bool

    @Environment(\.layoutDirection) private var layoutDirection

    @ViewBuilder
    var body: some View {
        ForEach(
            transientBrowsing.peekRequests.filter {
                $0.assignment == BrowserSpaceRuntimeAssignment(space: space)
                    && $0.sourceTabID == model.browser.selectedTabID(in: space.id)
            }
        ) { request in
            BrowserPeekOverlay(
                request: request,
                browser: model.browser,
                pages: model.pages,
                coordinator: transientBrowsing,
                reservedLeadingWidth: 0,
                layoutDirection: layoutDirection,
                spaceAccess: model.spaceAccess,
                frameInsets: BrowserChromeAppearance.device(windowCornerRadius: nil)
                    .pageInsets(docked: docked, direction: layoutDirection)
            )
            .environment(
                \.browserWebFocusRestorationGate,
                BrowserWebFocusRestorationGate(
                    browserChromeOwnsFocus: !request.isSelected(in: model.browser), pageChromeOwnsFocus: false)
            )
            .zIndex(BrowserRootMetrics.peekZIndex)
        }
    }
}
