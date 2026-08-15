import SwiftUI

struct BrowserQuickWindowContent: View {
    let model: BrowserQuickWindowModel
    let spaceAccess: BrowserSpaceAccessController
    let dismiss: () -> Void
    let openBrowserWindow: () -> Void

    var body: some View {
        Group {
            if let space = model.space,
                spaceAccess.isLocked(space)
            {
                BrowserSpaceAccessView(
                    space: space,
                    spaces: model.availableSpaces,
                    accessController: spaceAccess,
                    selectSpace: selectLockedSpace
                )
            } else if model.space != nil {
                BrowserQuickWindowUnlockedContent(
                    model: model,
                    spaceAccess: spaceAccess,
                    dismiss: dismiss,
                    openBrowserWindow: openBrowserWindow
                )
            } else {
                ContentUnavailableView(
                    "Space Unavailable",
                    systemImage: "square.grid.2x2",
                    description: Text(
                        "This Quick Window cannot reconnect to its original browsing profile."
                    )
                )
            }
        }
    }

    private func selectLockedSpace(
        _ assignment: BrowserSpaceRuntimeAssignment
    ) {
        guard let candidate = model.browser.space(matching: assignment) else {
            return
        }
        model.selectSpace(candidate)
    }
}

#Preview("Quick Window Content") {
    BrowserQuickWindowContent(
        model: BrowserQuickWindowPreviewFixture.makeModel(),
        spaceAccess: BrowserQuickWindowPreviewFixture.makeAccessController(),
        dismiss: {},
        openBrowserWindow: {}
    )
}
