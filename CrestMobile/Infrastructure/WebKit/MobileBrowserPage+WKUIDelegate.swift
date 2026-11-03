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
        guard elementInfo.linkURL != nil, linkPeekPressCoordinator.phase.holdsLink else {
            answerContextMenu(for: elementInfo, in: webView, completionHandler: completionHandler)
            return
        }
        // A held link opens Peek, not WebKit's link menu, which iPadOS asks
        // for even on a link without its callout. A press still deciding holds
        // the question until it does.
        linkPeekPressCoordinator.whenSettled { [weak self] opensPeek in
            guard let self else {
                completionHandler(nil)
                return
            }
            guard opensPeek else {
                answerContextMenu(for: elementInfo, in: webView, completionHandler: completionHandler)
                return
            }
            completionHandler(UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: nil))
            DispatchQueue.main.async { [weak self] in self?.dismissLinkMenu() }
        }
    }

    /// WebKit's menu for the element a person pressed: a link's with its live
    /// preview and the Spaces it can open in, and WebKit's own for the rest.
    private func answerContextMenu(
        for elementInfo: WKContextMenuElementInfo,
        in webView: WKWebView,
        completionHandler: @escaping @MainActor (UIContextMenuConfiguration?) -> Void
    ) {
        guard webView === self.webView,
            let context = navigationContext,
            let url = elementInfo.linkURL,
            ExternalWebLink.accepts(url),
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
                && self.linkDestinationHost.browser?.shownTab?.id == source.tabID
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
                    guard isCurrent(), let self, linkPeekPressCoordinator.phase != .committed else { return nil }
                    return MobileBrowserLinkPreviewController(
                        url: url, source: self.webView, isCurrent: isCurrent
                    )
                }
            ) { [weak self] suggested in
                // The press opened Peek while WebKit was preparing its menu.
                if self?.linkPeekPressCoordinator.phase == .committed { return UIMenu(children: []) }
                guard let self, isCurrent(),
                    let space = linkDestinationHost.browser?.spaceModel(source.spaceID)
                else { return UIMenu(children: suggested) }
                @MainActor func icon(for space: SpaceModel) -> UIImage? {
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
                                UIAction(title: space.settings.name, image: icon(for: space)) { _ in
                                    open(BrowserSpaceRuntimeAssignment(space: space))
                                }
                            }
                        ))
                }
                return UIMenu(children: [UIMenu(options: .displayInline, children: actions)] + suggested)
            })
    }

    /// WebKit asked for a held link's menu before the press opened Peek, as
    /// iPadOS does when the press begins; the menu closes as it opens.
    func webView(_ webView: WKWebView, contextMenuWillPresentForElement elementInfo: WKContextMenuElementInfo) {
        guard elementInfo.linkURL != nil, linkPeekPressCoordinator.phase == .committed else { return }
        DispatchQueue.main.async { [weak self] in self?.dismissLinkMenu() }
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
    /// `about:blank` popups writable. The page offers the popup to the core,
    /// which decides where it shows; Crest never loads that web view itself:
    /// WebKit drives the navigation it already scheduled. A popup the core
    /// refuses gets no window, and never a tab of its own.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        recordAcceptedPopup()
        let foreground = corePage.selectsOpenedWindow(gesture: navigationAction.linkGesture)
        let webKitPage = webKitPage
        let request = navigationAction.request
        return popupCoordinator.resolveOpen(for: navigationAction, currentURL: webView.url) { _ in
            webKitPage.offer(WebKitPopup(configuration: configuration), for: request, foreground: foreground)?.webView
        }
    }

    /// WebKit reports native picture-in-picture only to the UI delegate. The
    /// page's residency reads it back through its engine.
    @objc(_webView:hasVideoInPictureInPictureDidChange:)
    func webView(_ webView: WKWebView, hasVideoInPictureInPictureDidChange isActive: Bool) {
        webKitEngine?.hasVideoInPictureInPicture = isActive
        refreshMediaActivity()
    }

    /// The page's script asked to close its window, as `window.close()` does,
    /// once its document agreed to go. The core decides, as it does for every
    /// engine: only a page another page opened closes what owns it.
    func webViewDidClose(_ webView: WKWebView) {
        corePage.report(PageCloseRequested(pageID: corePage.id))
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        askScriptDialog(.alert, message: message, defaultText: nil, frame: frame) { _, _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        askScriptDialog(.confirm, message: message, defaultText: nil, frame: frame) { accepted, _ in
            completionHandler(accepted)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        askScriptDialog(.prompt, message: prompt, defaultText: defaultText, frame: frame) { accepted, text in
            completionHandler(accepted ? text ?? "" : nil)
        }
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
        answerMediaCapture(type, origin: origin, in: webView, decisionHandler: decisionHandler)
    }

    @available(iOS 27.0, *)
    func webView(
        _ webView: WKWebView,
        requestGeolocationPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        answerLocation(origin: origin, frame: frame, in: webView, decisionHandler: decisionHandler)
    }
}
