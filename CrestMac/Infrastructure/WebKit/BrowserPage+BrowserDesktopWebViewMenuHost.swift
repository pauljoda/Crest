import AppKit
import Foundation

extension BrowserPage: BrowserDesktopWebViewMenuHost {
    var opensLinksInCurrentSpace: Bool { navigationContext != nil }

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
        var menuContext = BrowserDesktopWebViewMenuContext(
            splitViewLinkDestination: splitViewDestination,
            imageDownloadURL: captured.imageURL
        )
        if let text = captured.selectionText, let context = navigationContext {
            menuContext.selectionSearch = linkDestinationHost.selectionSearch(
                for: text,
                from: BrowserTabRuntimeAssignment(
                    tabID: context.tabID, spaceID: context.spaceID,
                    profileID: context.assignment.profileID
                )
            )
        }
        if let url = captured.linkURL, let context = navigationContext {
            let source = BrowserTabRuntimeAssignment(
                tabID: context.tabID, spaceID: context.spaceID,
                profileID: context.assignment.profileID
            )
            if linkDestinationHost.canOpenLink(from: source) {
                menuContext.linkDestinations = BrowserDesktopLinkDestinations(
                    url: url, source: source,
                    spaces: linkDestinationHost.otherSpaces(from: source)
                )
            }
        }
        return menuContext
    }

    func openLinkInSplitView(_ url: URL) {
        guard let context = navigationContext,
            BrowserExternalURLPolicy.accepts(url)
        else { return }
        splitLinkHost.openLink(url, context.tabID, context.assignment)
    }

    func openLink(
        _ url: URL,
        from source: BrowserTabRuntimeAssignment,
        in destination: BrowserSpaceRuntimeAssignment
    ) {
        guard let context = navigationContext,
            context.tabID == source.tabID,
            context.spaceID == source.spaceID,
            context.assignment.profileID == source.profileID
        else { return }
        linkDestinationHost.openLink(url, from: source, in: destination)
    }

    func downloadImage(from url: URL) {
        let request = URLRequest(url: url)
        Task { @MainActor [weak self] in
            guard let self, let webView = webKitView else { return }
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


}
