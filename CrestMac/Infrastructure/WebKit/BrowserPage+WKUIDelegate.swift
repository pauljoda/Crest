import AppKit
import Combine
import Foundation
import Observation
import UniformTypeIdentifiers
import WebKit
import os

extension BrowserPage: WKUIDelegate {
    /// Returns the popup's web view built from WebKit's own configuration, which
    /// is what keeps `window.open()` non-null, `window.opener` connected, and
    /// `about:blank` popups writable. Crest never loads that web view itself:
    /// WebKit drives the navigation it already scheduled. `windowFeatures` is
    /// ignored because every popup becomes a tab.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        popupCoordinator.resolveOpen(
            for: navigationAction,
            currentURL: webView.url
        ) { [weak self] requestedURL in
            guard let self, let host else { return nil }
            return host.adoptPopupWebView(
                configuration: configuration,
                requestedURL: requestedURL,
                opener: self
            )
        }
    }

    /// Closes only tabs that web content opened. A hand-opened tab keeps its
    /// place: `window.close()` from a page the user navigated to would otherwise
    /// let any site discard the user's own tab.
    func webViewDidClose(_ webView: WKWebView) {
        guard wasOpenedAsPopup else { return }
        host?.closeWebContentInitiatedPage(self)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        dialogPresenter.presentAlert(
            message: message,
            request: frame.request,
            completion: completionHandler
        )
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        dialogPresenter.presentConfirm(
            message: message,
            request: frame.request,
            completion: completionHandler
        )
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        dialogPresenter.presentPrompt(
            message: prompt,
            defaultText: defaultText,
            request: frame.request,
            completion: completionHandler
        )
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        dialogPresenter.presentFileInput(
            parameters: parameters,
            request: frame.request,
            completion: completionHandler
        )
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        let permission = BrowserMediaPermission(type)
        let sitePermission = permission.sitePermission
        let siteOrigin = BrowserSiteOrigin(origin)
        switch permissionCenter.decision(
            for: sitePermission,
            origin: siteOrigin,
            in: spaceID
        ) {
        case .grantForSession, .grantPersistently:
            decisionHandler(.grant)
        case .denyForSession, .denyPersistently:
            decisionHandler(.deny)
        case .ask:
            dialogPresenter.presentMediaCapturePermission(
                permission: permission,
                origin: siteOrigin,
                topLevelURL: webView.url,
                spaceName: spaceName
            ) { response in
                switch response {
                case .allowOnce:
                    decisionHandler(.grant)
                case .grantPersistently:
                    self.permissionCenter.setDecision(
                        .grantPersistently,
                        for: sitePermission,
                        origin: siteOrigin,
                        in: self.spaceID
                    )
                    decisionHandler(.grant)
                case .denyPersistently:
                    self.permissionCenter.setDecision(
                        .denyPersistently,
                        for: sitePermission,
                        origin: siteOrigin,
                        in: self.spaceID
                    )
                    decisionHandler(.deny)
                }
            }
        }
    }
}
