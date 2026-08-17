import SwiftUI

struct BrowserQuickWindowSceneContent: View {
    let request: BrowserQuickWindowRequest?
    let context: BrowserQuickWindowBrowsingContext?
    let isRoutingExternalURL: Bool
    let spaceAccess: BrowserSpaceAccessController
    let pagePoolRegistry: BrowserPagePoolRegistry?
    let preferences: BrowserTransientBrowsingPreferences
    let previewModel: BrowserQuickWindowModel?
    let requestLifecycle: BrowserQuickWindowRequestLifecycle
    let openBrowserWindow: () -> Void

    var body: some View {
        Group {
            if let previewModel {
                BrowserQuickWindowView(
                    model: previewModel,
                    spaceAccess: spaceAccess,
                    openBrowserWindow: openBrowserWindow
                )
            } else if let request, let context {
                BrowserQuickWindowView(
                    request: request,
                    browser: context.browser,
                    pages: context.pages,
                    pagePoolRegistry: pagePoolRegistry,
                    spaceAccess: spaceAccess,
                    requestLifecycle: requestLifecycle,
                    openBrowserWindow: openBrowserWindow,
                    supportsLivePagePromotion:
                        context.supportsLivePagePromotion,
                    preferences: preferences
                )
                .id(
                    BrowserQuickWindowPresentationIdentity(
                        request: request,
                        context: context
                    )
                )
            } else if request != nil {
                ContentUnavailableView(
                    "Quick Window Unavailable",
                    systemImage: "rectangle.slash",
                    description: Text(
                        "Its original Space or browser window is no longer available."
                    )
                )
            } else if isRoutingExternalURL {
                ProgressView("Opening Quick Window…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
