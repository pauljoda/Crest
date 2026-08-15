import SwiftUI

struct BrowserNativeWindowControlsBridge: NSViewRepresentable {
    let isVisible: Bool

    func makeNSView(context: Context) -> BrowserNativeWindowControlsHostView {
        let view = BrowserNativeWindowControlsHostView()
        view.isVisible = isVisible
        return view
    }

    func updateNSView(
        _ nsView: BrowserNativeWindowControlsHostView,
        context: Context
    ) {
        nsView.isVisible = isVisible
    }

    static func dismantleNSView(
        _ nsView: BrowserNativeWindowControlsHostView,
        coordinator: Void
    ) {
        nsView.restoreWindowChrome()
    }
}

#Preview("Native Window Controls Bridge") {
    BrowserNativeWindowControlsBridge(isVisible: true)
        .frame(width: 1, height: 1)
}
