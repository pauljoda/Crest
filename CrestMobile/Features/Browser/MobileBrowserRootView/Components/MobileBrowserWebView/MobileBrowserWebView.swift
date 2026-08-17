import SwiftUI
import UIKit

struct MobileBrowserWebView: UIViewRepresentable {
    let page: MobileBrowserPage
    var viewport = MobileBrowserPageViewport.inline
    /// An unfocused split card's request to become the focused one.
    ///
    /// A SwiftUI `TapGesture` over web content is unreliable — the page's own
    /// gesture recognizers reach the touch first — so the recognizer is installed
    /// on the host beside the address-focus one, with `cancelsTouchesInView`
    /// false so the page still receives the tap it was given. `nil` outside a
    /// split, where there is no second card to focus.
    var requestFocus: (() -> Void)?

    func makeCoordinator() -> MobileBrowserWebViewCoordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MobileBrowserWebHostView {
        let host = MobileBrowserWebHostView()
        host.configureViewport(viewport)
        host.attach(page.webView)
        if context.coordinator.dismissFocusRecognizer.view == nil {
            host.addGestureRecognizer(
                context.coordinator.dismissFocusRecognizer
            )
        }
        installFocusRecognizerIfNeeded(on: host, coordinator: context.coordinator)
        return host
    }

    func updateUIView(_ host: MobileBrowserWebHostView, context: Context) {
        host.configureViewport(viewport)
        host.attach(page.webView)
        installFocusRecognizerIfNeeded(on: host, coordinator: context.coordinator)
    }

    private func installFocusRecognizerIfNeeded(
        on host: MobileBrowserWebHostView,
        coordinator: MobileBrowserWebViewCoordinator
    ) {
        coordinator.requestFocus = requestFocus
        guard requestFocus != nil,
            coordinator.cardFocusRecognizer.view == nil
        else { return }
        host.addGestureRecognizer(coordinator.cardFocusRecognizer)
    }

    static func dismantleUIView(
        _ host: MobileBrowserWebHostView,
        coordinator: MobileBrowserWebViewCoordinator
    ) {
        // The retained page model owns navigation. SwiftUI can dismantle and
        // recreate this transient host while a start-page navigation is being
        // handed off, so tearing the host down must not cancel the load.
        host.detach(stopsLoading: false)
    }
}
