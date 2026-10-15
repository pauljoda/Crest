import UIKit
import WebKit

/// Shows a page's model-owned web view where SwiftUI placed this host.
///
/// SwiftUI can hold two hosts for one page at once, and either can be the one
/// it dismantles first. During an animated replacement it keeps updating the
/// outgoing host after the incoming one claimed the web view; during a removal
/// transition the outgoing view can even build a new host for a page it only
/// now shows. The newest claim shows the web view, and when the host showing
/// it lets go, the web view returns to the newest host still asking for it, so
/// it always ends up in whichever host survives.
@MainActor
final class MobileBrowserWebHostView: UIView {
    // MARK: - Static Variables

    /// Every host that asked for a web view and has not let it go.
    private static let claimants = NSHashTable<MobileBrowserWebHostView>.weakObjects()
    /// The number of claims made so far, which orders them.
    private static var claimCount = 0

    // MARK: - Variables

    private weak var hostedWebView: WKWebView?
    private var hostedWebViewLeadingConstraint: NSLayoutConstraint?
    private var hostedWebViewTrailingConstraint: NSLayoutConstraint?
    private var hostedWebViewTopConstraint: NSLayoutConstraint?
    private var hostedWebViewBottomConstraint: NSLayoutConstraint?
    private var viewport = MobileBrowserPageViewport.inline
    /// When this host claimed `hostedWebView`: the newest claim is the largest.
    private var claim = 0

    // MARK: - Actions - Hosting

    /// Claims `webView` and shows it here. Asking again for the web view this
    /// host already claimed changes nothing, even when a newer host took it
    /// meanwhile: that host shows it until it lets go.
    func attach(_ webView: WKWebView) {
        guard hostedWebView !== webView else { return }
        detach(stopsLoading: false)
        Self.claimCount &+= 1
        claim = Self.claimCount
        hostedWebView = webView
        Self.claimants.add(self)
        show(webView)
    }

    /// Lets go of the web view this host claimed. When it was showing it, the
    /// web view stops loading if `stopsLoading` asks, leaves, and moves to
    /// the newest other host that still claims it.
    func detach(stopsLoading: Bool) {
        guard let hostedWebView else { return }
        Self.claimants.remove(self)
        let showsHostedWebView = hostedWebView.superview === self
        if stopsLoading, showsHostedWebView {
            hostedWebView.stopLoading()
        }
        if showsHostedWebView {
            hostedWebView.obscuredContentInsets = .zero
            hostedWebView.setMinimumViewportInset(
                .zero,
                maximumViewportInset: .zero
            )
            hostedWebView.scrollView.contentInset = .zero
            hostedWebView.scrollView.verticalScrollIndicatorInsets = .zero
            hostedWebView.removeFromSuperview()
        }
        hostedWebViewLeadingConstraint = nil
        hostedWebViewTrailingConstraint = nil
        hostedWebViewTopConstraint = nil
        hostedWebViewBottomConstraint = nil
        self.hostedWebView = nil
        guard showsHostedWebView else { return }
        Self.claimants.allObjects
            .filter { $0.hostedWebView === hostedWebView }
            .max { $0.claim < $1.claim }?
            .show(hostedWebView)
    }

    /// Puts `webView`, which this host claimed, on screen here.
    private func show(_ webView: WKWebView) {
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        let leadingConstraint = webView.leadingAnchor.constraint(equalTo: leadingAnchor)
        let trailingConstraint = webView.trailingAnchor.constraint(equalTo: trailingAnchor)
        let topConstraint = webView.topAnchor.constraint(equalTo: topAnchor)
        let bottomConstraint = webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        NSLayoutConstraint.activate([
            leadingConstraint,
            trailingConstraint,
            topConstraint,
            bottomConstraint,
        ])
        hostedWebViewLeadingConstraint = leadingConstraint
        hostedWebViewTrailingConstraint = trailingConstraint
        hostedWebViewTopConstraint = topConstraint
        hostedWebViewBottomConstraint = bottomConstraint
        applyViewportInsets()
    }

    // MARK: - Actions - Viewport

    func configureViewport(_ viewport: MobileBrowserPageViewport) {
        guard self.viewport != viewport else { return }
        self.viewport = viewport
        applyViewportInsets()
    }

    /// The viewport is applied from the value SwiftUI hands down rather than
    /// from this view's own `safeAreaInsets`, which a carousel cell inside a
    /// `ScrollView` never receives. `MobileBrowserPageViewport` carries the
    /// reasoning.
    private func applyViewportInsets() {
        guard let hostedWebView, hostedWebView.superview === self else { return }
        let frameInsets = viewport.webViewFrameInsets
        let overlayInsets = viewport.chromeOverlayInsets
        let viewportRange = viewport.viewportRangeInsets
        let scrollView = hostedWebView.scrollView

        // Keep the WebKit surface full-height so ordinary scrolling content
        // remains visible below Liquid Glass. The bottom-only content inset
        // extends the terminal scroll range without changing the web view's
        // frame or the viewport range WebKit reports to fixed, sticky, svh,
        // and lvh layouts.
        hostedWebViewLeadingConstraint?.constant = frameInsets.left
        hostedWebViewTrailingConstraint?.constant = -frameInsets.right
        hostedWebViewTopConstraint?.constant = frameInsets.top
        hostedWebViewBottomConstraint?.constant = -frameInsets.bottom
        hostedWebView.setMinimumViewportInset(
            viewportRange.minimum,
            maximumViewportInset: viewportRange.maximum
        )
        hostedWebView.obscuredContentInsets = overlayInsets
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentInset = overlayInsets
        scrollView.verticalScrollIndicatorInsets = overlayInsets
    }
}
