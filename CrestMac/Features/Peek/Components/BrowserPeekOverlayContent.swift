import SwiftUI

struct BrowserPeekOverlayContent<UnlockedContent: View>: View {
    let model: BrowserPeekModel
    let spaceAccess: BrowserSpaceAccessController
    let unlockedContent: UnlockedContent

    init(
        model: BrowserPeekModel,
        spaceAccess: BrowserSpaceAccessController,
        @ViewBuilder unlockedContent: () -> UnlockedContent
    ) {
        self.model = model
        self.spaceAccess = spaceAccess
        self.unlockedContent = unlockedContent()
    }

    var body: some View {
        if let space = model.space {
            if spaceAccess.isLocked(space) {
                BrowserSpaceAccessView(
                    space: space,
                    spaces: model.availableSpaces,
                    accessController: spaceAccess,
                    selectSpace: model.selectLockedSpace
                )
            } else {
                unlockedContent
            }
        } else {
            BrowserPeekUnavailableSpaceView(
                dismiss: model.dismissUnavailableRequest
            )
        }
    }
}
