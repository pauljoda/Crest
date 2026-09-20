import SwiftUI

struct BrowserExtensionPopupAnchorReader: NSViewRepresentable {
    @Binding var popupAnchor: BrowserExtensionPopupAnchor?

    func makeNSView(context: Context) -> BrowserExtensionPopupAnchorView {
        let view = BrowserExtensionPopupAnchorView()
        view.popupAnchorDidChange = { popupAnchor = $0 }
        return view
    }

    func updateNSView(
        _ nsView: BrowserExtensionPopupAnchorView,
        context: Context
    ) {
        nsView.popupAnchorDidChange = { popupAnchor = $0 }
    }
}
