import Foundation

extension BrowserPage: BrowserDesktopWebViewMenuHost {
    /// Answers the menu WebKit is building right now.
    ///
    /// The capture is taken unconditionally — even when the split refuses the
    /// link — so a report can never be inherited by a later menu. The store has
    /// the final say on whether the item appears at all: a pinned tab, a Start
    /// Page, and a group already at capacity each leave it out rather than
    /// showing a row that could not do anything.
    func takeSplitViewLinkDestination() -> URL? {
        guard let destination = linkContextCapture.takeLink(),
            let context = navigationContext,
            splitLinkHost.canOpenLink(context.tabID, context.assignment)
        else { return nil }
        return destination
    }

    func openLinkInSplitView(_ url: URL) {
        guard let context = navigationContext,
            BrowserExternalURLPolicy.accepts(url)
        else { return }
        splitLinkHost.openLink(url, context.tabID, context.assignment)
    }

    func discardSplitViewLinkCapture() {
        linkContextCapture.clear()
    }
}
