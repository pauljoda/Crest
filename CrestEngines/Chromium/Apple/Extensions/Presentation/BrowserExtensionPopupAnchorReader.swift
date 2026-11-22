import SwiftUI

struct BrowserExtensionPopupAnchorReader: NSViewRepresentable {
    @Binding var popupAnchor: BrowserExtensionPopupAnchor?
    /// The control this view stands for, so a keyboard-triggered popup can
    /// find it without a click. Omitted when only the click path needs it.
    var site: BrowserExtensionToolbarAnchorRegistry.Site?

    init(
        popupAnchor: Binding<BrowserExtensionPopupAnchor?> = .constant(nil),
        site: BrowserExtensionToolbarAnchorRegistry.Site? = nil
    ) {
        _popupAnchor = popupAnchor
        self.site = site
    }

    func makeNSView(context: Context) -> BrowserExtensionPopupAnchorView {
        let view = BrowserExtensionPopupAnchorView()
        view.popupAnchorDidChange = { popupAnchor = $0 }
        view.standing = context.environment.browserExtensionAnchorStanding
        view.site = site
        return view
    }

    func updateNSView(
        _ nsView: BrowserExtensionPopupAnchorView,
        context: Context
    ) {
        nsView.popupAnchorDidChange = { popupAnchor = $0 }
        nsView.standing = context.environment.browserExtensionAnchorStanding
        nsView.site = site
    }

    static func dismantleNSView(
        _ nsView: BrowserExtensionPopupAnchorView,
        coordinator: Void
    ) {
        nsView.site = nil
    }
}
