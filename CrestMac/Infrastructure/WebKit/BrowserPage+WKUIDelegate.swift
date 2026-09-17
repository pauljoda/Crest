import AppKit
import Combine
import Foundation
import Observation
import UniformTypeIdentifiers
import WebKit
import os

extension BrowserPage: BrowserExtensionDebuggerDialogHosting {}

extension BrowserPage: WKUIDelegate {
    /// The PDF HUD supplies its live document bytes through this desktop
    /// callback, rather than creating a WKDownload. Keep the supplied data:
    /// fetching the URL again can lose edits or an authenticated response.
    @objc(_webView:saveDataToFile:suggestedFilename:mimeType:originatingURL:)
    func webView(
        _ webView: WKWebView,
        saveDataToFile data: Data,
        suggestedFilename: String,
        mimeType: String,
        originatingURL: URL
    ) {
        guard webView === self.webView else { return }
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: profileID)
        let feedbackSource = BrowserMacDownloadFeedbackSource.capture(in: webView)
        Task { [downloadCenter, spaceName] in
            await downloadCenter.saveData(
                data, suggestedFilename: suggestedFilename, mimeType: mimeType,
                originatingURL: originatingURL, assignment: assignment,
                spaceName: spaceName, feedbackSource: feedbackSource)
        }
    }

    /// WebKit's desktop presentation callback also covers entry from its own
    /// video context menu, including videos inside cross-origin frames.
    @objc(_webView:hasVideoInPictureInPictureDidChange:)
    func webView(_ webView: WKWebView, hasVideoInPictureInPictureDidChange isActive: Bool) {
        pictureInPicture.nativePresentationDidChange(isActive: isActive)
    }

    /// Native PiP's Restore action asks the embedder to reveal its document.
    /// The ordinary Close action does not send this callback. Fullscreen also
    /// uses it, so only a still-valid PiP source may change tab selection.
    @objc(_webViewFullscreenMayReturnToInline:)
    func webViewFullscreenMayReturnToInline(_ webView: WKWebView) {
        guard webView === self.webView, pictureInPicture.canRestoreSource else { return }
        host?.restorePictureInPictureSourcePage(self)
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
                    opener: self,
                    selecting: navigationAction.selectsOpenedLink(
                        using: BrowserLinkPreferenceStore.shared.preferences
                    )
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
        if BrowserExtensionClipboardBridge.shared.handlePrompt(
            prompt, webView: webView, frame: frame, reply: completionHandler)
        {
            return
        }
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
            completion: { [weak self] urls in
                guard let self, let urls else {
                    completionHandler(nil)
                    return
                }
                do {
                    try self.fileUploadAccess.prepare(urls)
                    completionHandler(urls)
                } catch {
                    self.dialogPresenter.presentFileAccessFailure(
                        error,
                        request: frame.request
                    ) { completionHandler(nil) }
                }
            }
        )
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        guard webView === self.webView,
            let topLevelOrigin = webView.url.flatMap(BrowserSiteOrigin.init(url:))
        else {
            decisionHandler(.deny)
            return
        }
        BrowserMediaPermission(type).resolve(
            origin: BrowserSiteOrigin(origin),
            topLevelOrigin: topLevelOrigin,
            spaceID: spaceID,
            spaceName: spaceName,
            permissionCenter: permissionCenter,
            requests: sitePermissionRequests
        ) { [weak self] decision in
            if decision == .grant {
                self?.mediaCaptureSession.recordGrant(BrowserMediaPermission(type), origin: BrowserSiteOrigin(origin))
            }
            decisionHandler(decision)
        }
    }

    @available(macOS 27.0, *)
    func webView(
        _ webView: WKWebView,
        requestGeolocationPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        guard frame.webView === webView,
            let topLevelOrigin = webView.url.flatMap(BrowserSiteOrigin.init(url:))
        else {
            decisionHandler(.deny)
            return
        }
        let siteOrigin = BrowserSiteOrigin(origin)
        Task { @MainActor [weak self] in
            guard let self else {
                decisionHandler(.deny)
                return
            }
            let allowed = await sitePermissionRequests.authorize(
                .location, origin: siteOrigin, topLevelOrigin: topLevelOrigin,
                spaceID: spaceID, spaceName: spaceName, permissionCenter: permissionCenter)
            decisionHandler(allowed ? .grant : .deny)
        }
    }
}
