import SwiftUI

struct BrowserQuickWindowGeometryBridge: NSViewRepresentable {
    let pagePoolRegistry: BrowserPagePoolRegistry?
    let targetWindowID: UUID?
    /// The app the window opens over, where the person is in it, instead of
    /// over the page it came from.
    let source: BrowserQuickWindowSourceApp?

    func makeNSView(context: Context) -> BrowserQuickWindowGeometryHostView {
        BrowserQuickWindowGeometryHostView(
            pagePoolRegistry: pagePoolRegistry,
            targetWindowID: targetWindowID,
            source: source
        )
    }

    func updateNSView(
        _ nsView: BrowserQuickWindowGeometryHostView,
        context: Context
    ) {
        nsView.configure(
            pagePoolRegistry: pagePoolRegistry,
            targetWindowID: targetWindowID
        )
        nsView.updateWindowGeometry()
    }
}
