import SwiftUI

struct MobileBrowserTransientOverlayContent<UnlockedContent: View>: View {
    let requestID: UUID
    let space: BrowserSpace?
    let spaces: [BrowserSpace]
    let spaceAccess: BrowserSpaceAccessController
    let selectSpace: (BrowserSpaceRuntimeAssignment) -> Void
    let dismissUnavailable: () -> Void
    let unlockedContent: UnlockedContent

    init(
        requestID: UUID,
        space: BrowserSpace?,
        spaces: [BrowserSpace],
        spaceAccess: BrowserSpaceAccessController,
        selectSpace: @escaping (BrowserSpaceRuntimeAssignment) -> Void,
        dismissUnavailable: @escaping () -> Void,
        @ViewBuilder unlockedContent: () -> UnlockedContent
    ) {
        self.requestID = requestID
        self.space = space
        self.spaces = spaces
        self.spaceAccess = spaceAccess
        self.selectSpace = selectSpace
        self.dismissUnavailable = dismissUnavailable
        self.unlockedContent = unlockedContent()
    }

    var body: some View {
        if space == nil {
            MobileBrowserUnavailableTransientSpaceView(
                requestID: requestID,
                dismiss: dismissUnavailable
            )
        } else if let space, spaceAccess.isLocked(space) {
            BrowserSpaceAccessView(
                space: space,
                spaces: spaces,
                accessController: spaceAccess,
                selectSpace: selectSpace
            )
        } else {
            unlockedContent
        }
    }
}

#Preview {
    MobileBrowserTransientOverlayContent(
        requestID: MobileBrowserTransientPreviewFixture.requestID,
        space: MobileBrowserTransientPreviewFixture.space,
        spaces: [MobileBrowserTransientPreviewFixture.space],
        spaceAccess: MobileBrowserTransientPreviewFixture.makeAccessController(),
        selectSpace: { _ in },
        dismissUnavailable: {},
        unlockedContent: { Text("Transient page") }
    )
}
