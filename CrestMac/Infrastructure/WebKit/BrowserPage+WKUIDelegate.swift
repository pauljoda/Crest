import AppKit
import Combine
import Foundation
import Observation
import UniformTypeIdentifiers
import WebKit
import os

extension BrowserPage: BrowserExtensionDebuggerDialogHosting {}

extension BrowserPage: WKUIDelegate {
    /// WebKit's desktop presentation callback also covers entry from its own
    /// video context menu, including videos inside cross-origin frames.
    @objc(_webView:hasVideoInPictureInPictureDidChange:)
    func webView(_ webView: WKWebView, hasVideoInPictureInPictureDidChange isActive: Bool) {
        pictureInPicture.nativePresentationDidChange(isActive: isActive)
    }

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
        recordAcceptedPopup()
        return popupCoordinator.resolveOpen(
            for: navigationAction,
            currentURL: webView.url,
            navigateCurrent: { [weak self] request in
                guard let self, let host else { return false }
                return host.navigatePopupInCurrentPage(
                    request,
                    opener: self
                )
            },
            adopt: { [weak self] requestedURL in
                guard let self, let host else { return nil }
                return host.adoptPopupWebView(
                    configuration: configuration,
                    requestedURL: requestedURL,
                    opener: self
                )
            }
        )
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
        guard
            !interceptDebuggerDialog(
                .alert,
                message: message,
                frame: frame,
                resolve: { _, _ in completionHandler() }
            )
        else { return }
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
        guard
            !interceptDebuggerDialog(
                .confirm,
                message: message,
                frame: frame,
                resolve: { accept, _ in completionHandler(accept) }
            )
        else { return }
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
        guard
            !interceptDebuggerDialog(
                .prompt,
                message: prompt,
                defaultPrompt: defaultText ?? "",
                frame: frame,
                resolve: { _, text in completionHandler(text) }
            )
        else { return }
        dialogPresenter.presentPrompt(
            message: prompt,
            defaultText: defaultText,
            request: frame.request,
            completion: completionHandler
        )
    }

    /// Offers a dialog to an attached debugger session before Crest presents
    /// it. Returns true when the session took it, which means the page stays
    /// blocked until that session answers or the session ends.
    private func interceptDebuggerDialog(
        _ kind: BrowserExtensionDebuggerDialogKind,
        message: String,
        defaultPrompt: String? = nil,
        frame: WKFrameInfo,
        resolve: @escaping (Bool, String?) -> Void
    ) -> Bool {
        guard let interceptor = debuggerDialogInterceptor else { return false }
        return interceptor.intercept(
            BrowserExtensionDebuggerDialog(
                kind: kind,
                message: message,
                defaultPrompt: defaultPrompt,
                url: frame.request.url ?? webView.url
            ),
            resolve: resolve
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
        let siteOrigin =
            frame.request.url.flatMap { BrowserSiteOrigin(url: $0) }
            ?? BrowserSiteOrigin(origin)
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

    @available(macOS 27.0, *)
    func webView(
        _ webView: WKWebView,
        requestGeolocationPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        let siteOrigin =
            frame.request.url.flatMap { BrowserSiteOrigin(url: $0) }
            ?? BrowserSiteOrigin(origin)
        switch permissionCenter.decision(
            for: .location,
            origin: siteOrigin,
            in: spaceID
        ) {
        case .grantForSession, .grantPersistently:
            decisionHandler(.grant)
        case .denyForSession, .denyPersistently:
            decisionHandler(.deny)
        case .ask:
            Task { @MainActor [weak self] in
                guard let self else {
                    decisionHandler(.deny)
                    return
                }
                let response = await dialogPresenter.presentGeolocationPermission(
                    origin: siteOrigin,
                    topLevelURL: webView.url,
                    spaceName: spaceName
                )
                switch response {
                case .allowOnce:
                    decisionHandler(.grant)
                case .grantPersistently:
                    permissionCenter.setDecision(
                        .grantPersistently,
                        for: .location,
                        origin: siteOrigin,
                        in: spaceID
                    )
                    decisionHandler(.grant)
                case .denyPersistently:
                    permissionCenter.setDecision(
                        .denyPersistently,
                        for: .location,
                        origin: siteOrigin,
                        in: spaceID
                    )
                    decisionHandler(.deny)
                }
            }
        }
    }
}
