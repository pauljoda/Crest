import SwiftUI

struct BrowserSidebarAuxiliaryMouseMonitor: NSViewRepresentable {
    let isSidebarVisible: Bool
    let perform: @MainActor @Sendable (BrowserSidebarMouseButtonAction) -> Void

    func makeNSView(context: Context) -> BrowserSidebarAuxiliaryMouseObserverView {
        let view = BrowserSidebarAuxiliaryMouseObserverView(perform: perform)
        view.isHidden = !isSidebarVisible
        return view
    }

    func updateNSView(
        _ nsView: BrowserSidebarAuxiliaryMouseObserverView,
        context: Context
    ) {
        nsView.perform = perform
        nsView.isHidden = !isSidebarVisible
    }

    static func dismantleNSView(
        _ nsView: BrowserSidebarAuxiliaryMouseObserverView,
        coordinator: ()
    ) {
        nsView.stopMonitoring()
    }
}
