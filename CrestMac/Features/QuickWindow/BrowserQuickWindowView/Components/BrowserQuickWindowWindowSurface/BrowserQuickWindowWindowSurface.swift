import SwiftUI

struct BrowserQuickWindowWindowSurface: View {
    let model: BrowserQuickWindowModel
    let spaceAccess: BrowserSpaceAccessController
    let pagePoolRegistry: BrowserPagePoolRegistry?
    let dismiss: () -> Void
    let openBrowserWindow: () -> Void

    var body: some View {
        BrowserQuickWindowContent(
            model: model,
            spaceAccess: spaceAccess,
            dismiss: dismiss,
            openBrowserWindow: openBrowserWindow
        )
        .modifier(BrowserQuickWindowAppearanceModifier(model: model))
        .onChange(of: selectedSpaceIsLocked, initial: true) { _, isLocked in
            if isLocked {
                model.releaseForUnavailableSpace()
            }
        }
        .background {
            BrowserQuickWindowGeometryBridge(
                pagePoolRegistry: pagePoolRegistry,
                targetWindowID: model.presentedRequest.targetWindowID
            )
        }
        .background {
            BrowserNativeWindowControlsBridge(isVisible: true)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onDisappear(perform: model.releaseForDismissal)
    }

    private var selectedSpaceIsLocked: Bool {
        guard let space = model.space else { return false }
        return spaceAccess.isLocked(space)
    }
}
