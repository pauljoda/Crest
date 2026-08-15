import SwiftUI

struct BrowserSidebarAuxiliaryMouseMonitor: NSViewRepresentable {
    let perform: @MainActor @Sendable (BrowserSidebarMouseButtonAction) -> Void

    func makeNSView(context: Context) -> BrowserSidebarAuxiliaryMouseObserverView {
        BrowserSidebarAuxiliaryMouseObserverView(perform: perform)
    }

    func updateNSView(
        _ nsView: BrowserSidebarAuxiliaryMouseObserverView,
        context: Context
    ) {
        nsView.perform = perform
    }

    static func dismantleNSView(
        _ nsView: BrowserSidebarAuxiliaryMouseObserverView,
        coordinator: ()
    ) {
        nsView.stopMonitoring()
    }
}
