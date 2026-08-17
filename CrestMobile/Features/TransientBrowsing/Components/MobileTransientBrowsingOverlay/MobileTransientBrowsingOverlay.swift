import SwiftUI

struct MobileTransientBrowsingOverlay: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore?
    let coordinator: BrowserTransientBrowsingCoordinator
    let spaceAccess: BrowserSpaceAccessController
    let didPromote: () -> Void

    var body: some View {
        MobileTransientBrowsingRequestOverlay(
            presentation: presentation,
            browser: browser,
            pages: pages,
            coordinator: coordinator,
            spaceAccess: spaceAccess,
            didPromote: didPromote
        )
    }

    private var presentation: MobileTransientBrowsingPresentation? {
        if let request = coordinator.quickWindowRequest {
            return MobileTransientBrowsingPresentation(
                request: .quickWindow(request),
                phase: .committed
            )
        }
        guard let request = coordinator.peekRequest else { return nil }
        return MobileTransientBrowsingPresentation(
            request: .peek(request),
            phase: coordinator.peekPresentationPhase ?? .committed
        )
    }
}
