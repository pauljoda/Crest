import SwiftUI

struct BrowserSidebarAuxiliaryMouseMonitor: NSViewRepresentable {
    let isSidebarVisible: Bool
    let perform: @MainActor @Sendable (BrowserSidebarMouseButtonAction) -> Void
    let navigationTargets:
        @MainActor @Sendable () -> [any BrowserSidebarMouseNavigationTarget]

    func makeNSView(context: Context) -> BrowserSidebarAuxiliaryMouseObserverView {
        let view = BrowserSidebarAuxiliaryMouseObserverView(
            perform: perform,
            navigationTargets: navigationTargets
        )
        view.isHidden = !isSidebarVisible
        return view
    }

    func updateNSView(
        _ nsView: BrowserSidebarAuxiliaryMouseObserverView,
        context: Context
    ) {
        nsView.perform = perform
        nsView.navigationTargets = navigationTargets
        nsView.isHidden = !isSidebarVisible
    }

    static func dismantleNSView(
        _ nsView: BrowserSidebarAuxiliaryMouseObserverView,
        coordinator: ()
    ) {
        nsView.stopMonitoring()
    }
}
