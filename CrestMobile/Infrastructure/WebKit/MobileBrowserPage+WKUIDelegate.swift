import Dispatch
import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

extension MobileBrowserPage: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
        completionHandler: @escaping @MainActor (UIContextMenuConfiguration?) -> Void
    ) {
        contextMenuPreviewCommit = nil
        guard webView === self.webView,
            let context = navigationContext,
            let url = elementInfo.linkURL,
            BrowserCorePolicy.acceptsExternalURL(url),
            let window = webView.window
        else {
            // WebKit supplies image and detected-data previews and their actions.
            completionHandler(nil)
            return
        }
        let source = BrowserTabRuntimeAssignment(
            tabID: context.tabID, spaceID: context.spaceID, profileID: context.assignment.profileID
        )
        let generation = committedNavigationCount
        let isCurrent: () -> Bool = { [weak self, weak window] in
            guard let self, let window else { return false }
            return self.webView.window === window
                && self.committedNavigationCount == generation
                && self.navigationContext?.tabID == source.tabID
                && self.navigationContext?.assignment
                    == BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID)
                && self.linkDestinationHost.browser?.selectedTab?.id == source.tabID
                && self.linkDestinationHost.canOpenLink(from: source)
        }
        let open: (BrowserSpaceRuntimeAssignment) -> Void = { [weak self] destination in
            guard isCurrent(), let self else { return }
            self.linkDestinationHost.openLink(url, from: source, in: destination)
        }
        let currentSpace = BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID)
        contextMenuPreviewCommit = { open(currentSpace) }
        completionHandler(
            UIContextMenuConfiguration(
                identifier: nil,
                previewProvider: { [weak self] in
                    guard isCurrent(), let self else { return nil }
                    return MobileBrowserLinkPreviewController(
                        url: url, source: self.webView, isCurrent: isCurrent
                    )
                }
            ) { [weak self] suggested in
                guard let self, isCurrent(),
                    let space = linkDestinationHost.browser?.session.space(id: source.spaceID)
                else { return UIMenu(children: suggested) }
                @MainActor func icon(for space: BrowserSpace) -> UIImage? {
                    let renderer = ImageRenderer(content: BrowserSpaceIdentityIcon(space: space))
                    renderer.scale = window.traitCollection.displayScale
                    return renderer.uiImage?.withRenderingMode(.alwaysOriginal)
                }
                let current = UIAction(
                    title: String(localized: "Open in Current Space"), image: icon(for: space)
                ) { _ in
                    open(currentSpace)
                }
                var actions: [UIMenuElement] = [current]
                let spaces = linkDestinationHost.otherSpaces(from: source)
                if !spaces.isEmpty {
                    actions.append(
                        UIMenu(
                            title: String(localized: "Open in Other Space"),
                            image: UIImage(systemName: "square.stack"),
                            children: spaces.map { space in
                                UIAction(title: space.name, image: icon(for: space)) { _ in
                                    open(BrowserSpaceRuntimeAssignment(space: space))
                                }
                            }
                        ))
                }
                return UIMenu(children: [UIMenu(options: .displayInline, children: actions)] + suggested)
            })
    }

    func webView(
        _ webView: WKWebView,
        contextMenuForElement elementInfo: WKContextMenuElementInfo,
        willCommitWithAnimator animator: any UIContextMenuInteractionCommitAnimating
    ) {
        guard webView === self.webView, let commit = contextMenuPreviewCommit else { return }
        animator.addCompletion(commit)
    }

    func webView(_ webView: WKWebView, contextMenuDidEndForElement elementInfo: WKContextMenuElementInfo) {
        contextMenuPreviewCommit = nil
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
            currentURL: webView.url
        ) { [weak self] requestedURL in
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
    }

    /// WebKit reports native picture-in-picture only to the UI delegate. The
    /// page's residency reads it back through its engine.
    @objc(_webView:hasVideoInPictureInPictureDidChange:)
    func webView(_ webView: WKWebView, hasVideoInPictureInPictureDidChange isActive: Bool) {
        webKitEngine?.hasVideoInPictureInPicture = isActive
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
        MobileBrowserDialogPresenter.presentAlert(
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
        MobileBrowserDialogPresenter.presentConfirmation(
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
        MobileBrowserDialogPresenter.presentPrompt(
            message: prompt,
            defaultText: defaultText,
            request: frame.request,
            completion: completionHandler
        )
    }

    // Leave runOpenPanelWith unimplemented on iOS. WebKit's native upload flow
    // offers Photos, camera and Files using the input's accept/capture/multiple
    // attributes, owns presentation for this web view, and retains upload copies
    // for the content view's lifetime. A custom delegate replaces that entire flow.

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
                self?.sitePermissionSession.recordMediaGrant(
                    BrowserMediaPermission(type), origin: BrowserSiteOrigin(origin))
            }
            decisionHandler(decision)
        }
    }

    @available(iOS 27.0, *)
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
