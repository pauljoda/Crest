import SwiftUI

struct MobileTransientBrowsingRequestOverlay: View {
    let presentation: MobileTransientBrowsingPresentation?
    let browser: BrowserStore
    let pages: MobileBrowserPageStore?
    let coordinator: BrowserTransientBrowsingCoordinator
    let spaceAccess: BrowserSpaceAccessController
    let didPromote: () -> Void

    @ViewBuilder
    var body: some View {
        if let presentation, let pages {
            MobileBrowserTransientOverlay(
                request: presentation.request,
                presentationPhase: presentation.phase,
                browser: browser,
                pages: pages,
                coordinator: coordinator,
                spaceAccess: spaceAccess,
                didPromote: didPromote
            )
            .id(presentation.request.renderIdentity)
            .zIndex(MobileBrowserTransientLayout.overlayLayer)
        } else if let presentation {
            MobileTransientBrowsingPreviewSurface(
                request: presentation.request
            )
            .id(presentation.request.renderIdentity)
            .zIndex(MobileBrowserTransientLayout.overlayLayer)
        }
    }
}

#Preview {
    MobileTransientBrowsingRequestOverlay(
        presentation: MobileBrowserTransientPreviewFixture.presentation,
        browser: MobileBrowserTransientPreviewFixture.makeBrowser(),
        pages: nil,
        coordinator: BrowserTransientBrowsingCoordinator(),
        spaceAccess: MobileBrowserTransientPreviewFixture.makeAccessController(),
        didPromote: {}
    )
}
