import SwiftUI

struct BrowserQuickWindowWindowSurface: View {
    let model: BrowserQuickWindowModel
    let spaceAccess: BrowserSpaceAccessController
    let pagePoolRegistry: BrowserPagePoolRegistry?
    /// Closes the window without asking its page. Every close the content
    /// asks for is the window closing itself: its page closed, moved to a tab
    /// or went to the archive.
    let dismiss: () -> Void
    let openBrowserWindow: () -> Void
    /// The app the window opens over: the one another app's link, or the
    /// Quick Window keys pressed there, came from.
    var source: BrowserQuickWindowSourceApp?

    var body: some View {
        BrowserQuickWindowContent(
            model: model,
            spaceAccess: spaceAccess,
            dismiss: dismiss,
            openBrowserWindow: openBrowserWindow
        )
        .modifier(BrowserQuickWindowAppearanceModifier(model: model))
        // The window's smallest size, which the hosting controller hands the
        // window: its toolbar and the palette under it fit no narrower.
        .frame(minWidth: BrowserQuickWindowLayout.minimumWidth, minHeight: BrowserQuickWindowLayout.minimumHeight)
        .onChange(of: selectedSpaceIsLocked, initial: true) { _, isLocked in
            if isLocked {
                model.releaseForUnavailableSpace()
            }
        }
        .background {
            BrowserQuickWindowGeometryBridge(
                pagePoolRegistry: pagePoolRegistry,
                targetWindowID: model.presentedRequest.targetWindowID,
                source: source
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
        guard let space = model.spaceModel else { return false }
        return spaceAccess.isLocked(space)
    }
}

#Preview("Quick Window") {
    BrowserQuickWindowWindowSurface(
        model: BrowserQuickWindowPreviewFixture.makeModel(),
        spaceAccess: BrowserQuickWindowPreviewFixture.makeAccessController(), pagePoolRegistry: nil, dismiss: {},
        openBrowserWindow: {}
    )
    .frame(width: BrowserQuickWindowLayout.defaultWidth, height: BrowserQuickWindowLayout.defaultHeight)
}
