import SwiftUI

/// Hosts the copy's browser in a view of its own, apart from setup's SwiftUI
/// hierarchy: no safe area of setup's window reaches it, so the browser lays
/// out from its own top as a window of its own would, and only what `content`
/// carries of the environment reaches it. Its layer rounds its corners, which
/// clips the browser's own AppKit views too.
struct BrowserSetupLiveWindowHost<Content: View>: NSViewRepresentable {
    // MARK: - Variables

    let content: Content
    let cornerRadius: CGFloat

    // MARK: - Actions - Hosting

    func makeNSView(context: Context) -> NSHostingView<Content> {
        let view = NSHostingView(rootView: content)
        view.safeAreaRegions = []
        view.sizingOptions = []
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        view.layer?.cornerCurve = .continuous
        view.layer?.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ view: NSHostingView<Content>, context: Context) {
        view.rootView = content
        view.layer?.cornerRadius = cornerRadius
    }
}
