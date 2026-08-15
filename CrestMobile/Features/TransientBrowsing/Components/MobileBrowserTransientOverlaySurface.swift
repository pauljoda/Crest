import SwiftUI

struct MobileBrowserTransientOverlaySurface: View {
    let model: MobileBrowserTransientOverlayModel
    let presentationPhase: BrowserPeekPresentationPhase
    let spaceAccess: BrowserSpaceAccessController

    var body: some View {
        MobileBrowserTransientOverlayContent(
            requestID: model.request.id,
            space: model.space,
            spaces: model.availableSpaces,
            spaceAccess: spaceAccess,
            selectSpace: model.selectLockedSpace,
            dismissUnavailable: model.dismissUnavailableRequest
        ) {
            MobileBrowserTransientUnlockedContent(
                model: model,
                presentationPhase: presentationPhase
            )
        }
        .modifier(
            MobileBrowserTransientLifecycleModifier(
                model: model,
                spaceAccess: spaceAccess
            )
        )
    }
}

#Preview {
    MobileBrowserTransientOverlaySurface(
        model: MobileBrowserTransientPreviewFixture.makeModel(),
        presentationPhase: .committed,
        spaceAccess: MobileBrowserTransientPreviewFixture.makeAccessController()
    )
}
