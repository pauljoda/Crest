import AppKit
import Foundation

extension BrowserPage: BrowserDesktopWebViewMenuHost {
    /// Answers the menu WebKit is building right now.
    ///
    /// The capture is taken unconditionally — even when the split refuses the
    /// link — so a report can never be inherited by a later menu. The store has
    /// the final say on whether the item appears at all: a pinned tab, a Start
    /// Page, and a group already at capacity each leave it out rather than
    /// showing a row that could not do anything.
    func takeMenuContext() -> BrowserDesktopWebViewMenuContext? {
        guard let captured = linkContextCapture.take() else { return nil }
        let splitViewDestination: URL?
        if let destination = captured.linkURL,
            let context = navigationContext,
            splitLinkHost.canOpenLink(context.tabID, context.assignment)
        {
            splitViewDestination = destination
        } else {
            splitViewDestination = nil
        }
        return BrowserDesktopWebViewMenuContext(
            splitViewLinkDestination: splitViewDestination,
            imageDownloadURL: captured.imageURL,
            extensionContext: extensionMenuContext(from: captured)
        )
    }

    func extensionMenuItems(
        for context: BrowserDesktopWebViewMenuContext
    ) -> [NSMenuItem] {
        guard let extensionContext = context.extensionContext else { return [] }
        return extensionWebpageMenuItems(extensionContext)
    }

    func openLinkInSplitView(_ url: URL) {
        guard let context = navigationContext,
            BrowserExternalURLPolicy.accepts(url)
        else { return }
        splitLinkHost.openLink(url, context.tabID, context.assignment)
    }

    func downloadImage(from url: URL) {
        let request = URLRequest(url: url)
        Task { @MainActor [weak self] in
            guard let self else { return }
            let download = await webView.startDownload(using: request)
            guard !Task.isCancelled else {
                _ = await download.cancel()
                return
            }
            downloadCenter.start(
                download,
                in: webView,
                profileID: profileID,
                spaceID: spaceID,
                spaceName: spaceName,
                isUserInitiated: true
            )
        }
    }

    func discardSplitViewLinkCapture() {
        linkContextCapture.clear()
    }

    private func extensionMenuContext(
        from captured: BrowserLinkContext
    ) -> BrowserExtensionWebpageMenuContext? {
        guard extensionBaseURL == nil,
            let pageURL = webView.url,
            let documentURL = captured.documentURL ?? webView.url
        else { return nil }
        return BrowserExtensionWebpageMenuContext(
            pageURL: pageURL,
            documentURL: documentURL,
            linkURL: captured.linkURL,
            sourceURL: captured.sourceURL,
            mediaType: captured.mediaType,
            selectionText: captured.selectionText,
            isEditable: captured.isEditable,
            isMainFrame: captured.isMainFrame
        )
    }
}
