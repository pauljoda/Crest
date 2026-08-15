import UIKit
import WebKit

@MainActor
final class MobileBrowserWebHostView: UIView {
    private weak var hostedWebView: WKWebView?
    private var hostedWebViewLeadingConstraint: NSLayoutConstraint?
    private var hostedWebViewTrailingConstraint: NSLayoutConstraint?
    private var hostedWebViewTopConstraint: NSLayoutConstraint?
    private var hostedWebViewBottomConstraint: NSLayoutConstraint?
    private var viewport = MobileBrowserPageViewport.inline

    func configureViewport(_ viewport: MobileBrowserPageViewport) {
        guard self.viewport != viewport else { return }
        self.viewport = viewport
        applyViewportInsets()
    }

    func attach(_ webView: WKWebView) {
        guard hostedWebView !== webView || webView.superview !== self else {
            return
        }

        detach(stopsLoading: false)
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
        hostedWebView = webView
        applyViewportInsets()
    }

    func detach(stopsLoading: Bool) {
        guard let hostedWebView else { return }
        let ownsHostedWebView = hostedWebView.superview === self
        if stopsLoading, ownsHostedWebView {
            hostedWebView.stopLoading()
        }
        if ownsHostedWebView {
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
    }

    /// The viewport is applied from the value SwiftUI hands down rather than
    /// from this view's own `safeAreaInsets`, which a carousel cell inside a
    /// `ScrollView` never receives. `MobileBrowserPageViewport` carries the
    /// reasoning.
    private func applyViewportInsets() {
        guard let hostedWebView else { return }
        let obscuresSystemSafeAreas = viewport.obscuresSystemSafeAreas
        let safeAreaInsets = viewport.systemSafeAreaInsets
        let bottomChromeHeight = viewport.bottomChromeHeight
        let frameInsets =
            obscuresSystemSafeAreas
            ? MobileBrowserViewportPolicy.webViewFrameInsets(
                safeAreaInsets: safeAreaInsets,
                bottomChromeHeight: bottomChromeHeight
            )
            : .zero
        let overlayInsets =
            obscuresSystemSafeAreas
            ? MobileBrowserViewportPolicy.chromeOverlayInsets(
                safeAreaInsets: safeAreaInsets,
                bottomChromeHeight: bottomChromeHeight
            )
            : .zero
        let viewportRange =
            obscuresSystemSafeAreas
            ? MobileBrowserViewportPolicy.viewportRangeInsets(
                safeAreaInsets: safeAreaInsets
            )
            : (minimum: UIEdgeInsets.zero, maximum: UIEdgeInsets.zero)
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
