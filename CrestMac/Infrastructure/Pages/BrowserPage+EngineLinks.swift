import AppKit

/// Link destinations for an engine that asks the core about its links itself
/// and runs its own link menu and drags. They run the same shared commands the
/// WebKit menu and navigation delegate use.
extension BrowserPage {
    /// Opens `url` as a new card beside the tab this page presents.
    func openLinkInSplitView(_ url: URL) {
        guard let context = navigationContext,
            ExternalWebLink.accepts(url)
        else { return }
        _ = splitLinkHost.openLink(url, context.tabID, context.assignment)
    }

    /// The other Spaces of this page's window that a link or the page itself
    /// can open in, in picker order and split where one group ends and the
    /// next begins; none while the page shows no tab.
    var otherSpaceGroups: [[SpaceModel]] {
        guard let context = navigationContext else { return [] }
        return linkDestinationHost.otherSpaceGroups(
            from: BrowserTabRuntimeAssignment(
                tabID: context.tabID, spaceID: context.spaceID, profileID: context.assignment.profileID))
    }

    /// Opens `url` in a Quick Window over this page's window, in the session
    /// of `space`, whose crest and color the Quick Window wears. Keep moves it
    /// into that Space as a tab.
    @discardableResult
    func openInQuickWindow(_ url: URL, in space: SpaceModel) -> Bool {
        guard ExternalWebLink.accepts(url), let pool = windowRouting?.pool, let present = pool.popupWindowPresenter
        else { return false }
        present(
            BrowserQuickWindowRequest(
                url: url, spaceAssignment: BrowserSpaceRuntimeAssignment(space: space), targetWindowID: pool.windowID))
        return true
    }

    /// Opens the Peek the core chose for a link the engine kept in the page.
    /// A page that has no tab to open it from, or is out of its window, drops
    /// the link its engine staged for the Peek's first load.
    func openRequestedPeek(
        to destination: URL, decision: LinkNavigationDecision, stagedLink: BrowserEngineNavigation?
    ) {
        guard nativeView.window != nil,
            let request = decision.peekRequest(
                destinationURL: destination, context: navigationContext, engineNavigation: stagedLink)
        else {
            if let stagedLink { corePage.discardStagedLink(stagedLink) }
            return
        }
        openPeek(request)
    }
}
