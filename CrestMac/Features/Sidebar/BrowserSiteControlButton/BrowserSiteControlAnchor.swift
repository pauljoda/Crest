import SwiftUI

/// A native view the composition places behind the Site Controls button, so an
/// engine can anchor its own popups to the control that lists its extensions.
struct BrowserSiteControlAnchor: Sendable {
    let makeView: @MainActor @Sendable () -> NSView
}

extension EnvironmentValues {
    /// Nil when the composed engine anchors nothing there.
    @Entry var browserSiteControlAnchor: BrowserSiteControlAnchor? = nil
}

struct BrowserSiteControlAnchorHost: NSViewRepresentable {
    let anchor: BrowserSiteControlAnchor

    func makeNSView(context: Context) -> NSView {
        let view = anchor.makeView()
        updateNSView(view, context: context)
        return view
    }

    /// Gives the anchor the standing of the Site Controls it sits behind, so
    /// a split card's copy answers only while its card has focus.
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? BrowserExtensionAnchorStandingView)?.standing =
            context.environment.browserExtensionAnchorStanding
    }
}
