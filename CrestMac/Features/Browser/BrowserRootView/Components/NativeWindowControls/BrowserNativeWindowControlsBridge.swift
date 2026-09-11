import SwiftUI

struct BrowserNativeWindowControlsBridge: NSViewRepresentable, Animatable {
    let isVisible: Bool
    nonisolated var sidebarPosition: CGFloat = 0
    nonisolated var animatableData: CGFloat {
        get { sidebarPosition }
        set { sidebarPosition = newValue }
    }
    var sidebarWidth: CGFloat = BrowserChromeLayout.sidebarIdealWidth

    func makeNSView(context: Context) -> BrowserNativeWindowControlsHostView {
        let view = BrowserNativeWindowControlsHostView()
        view.sidebarPosition = sidebarPosition
        view.sidebarWidth = sidebarWidth
        view.isVisible = isVisible
        return view
    }

    func updateNSView(
        _ nsView: BrowserNativeWindowControlsHostView,
        context: Context
    ) {
        nsView.sidebarPosition = sidebarPosition
        nsView.sidebarWidth = sidebarWidth
        nsView.isVisible = isVisible
        nsView.applyBrowserChrome()
    }

    static func dismantleNSView(
        _ nsView: BrowserNativeWindowControlsHostView,
        coordinator: Void
    ) {
        nsView.restoreWindowChrome()
    }
}
