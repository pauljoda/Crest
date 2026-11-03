import SwiftUI

struct BrowserQuickWindowGeometryBridge: NSViewRepresentable {
    let pagePoolRegistry: BrowserPagePoolRegistry?
    let targetWindowID: UUID?
    /// Whether the window opens on the display under the pointer instead of
    /// over the page it came from.
    let opensWherePersonIs: Bool

    func makeNSView(context: Context) -> BrowserQuickWindowGeometryHostView {
        BrowserQuickWindowGeometryHostView(
            pagePoolRegistry: pagePoolRegistry,
            targetWindowID: targetWindowID,
            opensWherePersonIs: opensWherePersonIs
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
