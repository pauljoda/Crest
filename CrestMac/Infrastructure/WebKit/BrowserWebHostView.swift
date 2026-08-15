import AppKit
import os
import WebKit

@MainActor
final class BrowserWebHostView: NSView {
    private static let lifecycleSignposter = OSSignposter(
        subsystem: "com.pauldavis.crest",
        category: "WebKitLifecycle"
    )

    private weak var hostedWebView: WKWebView?

    func attach(_ webView: WKWebView) {
        if hostedWebView === webView {
            if webView.superview === self {
                return
            }
            if webView.superview != nil {
                // A newer SwiftUI host has already taken ownership. A stale
                // update from a disappearing Peek must not steal it back.
                hostedWebView = nil
                return
            }
        }

        let attachInterval = Self.lifecycleSignposter.beginInterval(
            "Attach WKWebView"
        )
        defer {
            Self.lifecycleSignposter.endInterval(
                "Attach WKWebView",
                attachInterval
            )
        }

        let detachInterval = Self.lifecycleSignposter.beginInterval(
            "Detach Previous WKWebView"
        )
        detach()
        Self.lifecycleSignposter.endInterval(
            "Detach Previous WKWebView",
            detachInterval
        )

        let removeInterval = Self.lifecycleSignposter.beginInterval(
            "Remove WKWebView From Parent"
        )
        webView.removeFromSuperview()
        Self.lifecycleSignposter.endInterval(
            "Remove WKWebView From Parent",
            removeInterval
        )

        // WebKit temporarily reparents rendering surfaces for features such as
        // the docked Web Inspector. Frame-based layout lets those surfaces keep
        // their geometry instead of inheriting constraints from the SwiftUI
        // host and ending up mounted but visually blank.
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]
        webView.frame = bounds

        let addInterval = Self.lifecycleSignposter.beginInterval(
            "Add WKWebView Subview"
        )
        addSubview(webView)
        Self.lifecycleSignposter.endInterval(
            "Add WKWebView Subview",
            addInterval
        )
        hostedWebView = webView
    }

    func detach() {
        guard let hostedWebView else { return }
        if hostedWebView.superview === self {
            hostedWebView.removeFromSuperview()
        }
        self.hostedWebView = nil
    }
}
