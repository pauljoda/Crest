import SwiftUI

struct BrowserQuickWindowGeometryBridge: NSViewRepresentable {
    let pagePoolRegistry: BrowserPagePoolRegistry?
    let targetWindowID: BrowserWindowID?

    func makeNSView(context: Context) -> BrowserQuickWindowGeometryHostView {
        BrowserQuickWindowGeometryHostView(
            pagePoolRegistry: pagePoolRegistry,
            targetWindowID: targetWindowID
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

    static func dismantleNSView(
        _ nsView: BrowserQuickWindowGeometryHostView,
        coordinator: Void
    ) {
        nsView.stopObserving()
    }
}
