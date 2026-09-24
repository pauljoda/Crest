#if DEBUG
    import Foundation

    extension BrowserStore {
        /// Puts a visit to `url` first in the history of `spaceID`, the Space
        /// this window shows unless named, as the core records one when a page
        /// finishes loading, for tests that need history without a page.
        func seedVisit(to url: URL, titled title: String, in spaceID: SpaceID? = nil, at date: Date = .now) {
            guard let index = session.spaces.firstIndex(where: { $0.id == (spaceID ?? selectedSpaceID) }) else {
                return
            }
            session.spaces[index].history.insert(
                BrowserHistoryEntry(url: url, title: title, firstVisitedAt: date, lastVisitedAt: date), at: 0)
        }

        /// Gives the tab this window shows the address and title a page's
        /// recorded navigation would, for tests of what windows show. A nil
        /// `url` keeps the tab's address.
        func seedSelectedTabNavigation(to url: URL?, titled title: String) {
            guard let spaceIndex = session.spaces.firstIndex(where: { $0.id == selectedSpaceID }),
                let tabID = selectedTab?.id,
                let tabIndex = session.spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID })
            else { return }
            if let url { session.spaces[spaceIndex].tabs[tabIndex].url = url }
            session.spaces[spaceIndex].tabs[tabIndex].title = title
        }

        /// Opens a page through the core for `tabID` in `spaceID`, or for a
        /// Quick Window or Peek request when `tabID` is nil, on a core whose
        /// default engine is WebKit. The page hosts nothing: a test reports
        /// what its engine would see with `finishNavigation(of:to:titled:icon:)`.
        func openReportingPage(for tabID: TabID?, in spaceID: SpaceID? = nil) -> CorePage? {
            openPage(in: spaceID ?? selectedSpaceID, for: tabID) { _ in NSObject() }?.page
        }

        /// Reports that `page` loaded a new document at `url`, found `icon`
        /// for it and finished titled `title`, then applies what the core
        /// recorded.
        func finishNavigation(of page: CorePage, to url: URL, titled title: String, icon: Data? = nil) {
            page.report(NavigationStarted(pageID: page.id, url: url.absoluteString, sameDocument: false))
            page.report(NavigationCommitted(pageID: page.id, url: url.absoluteString, sameDocument: false))
            if let icon {
                page.report(PageIconChanged(pageID: page.id, url: url.absoluteString, accent: nil), icon: icon)
            }
            page.report(NavigationFinished(pageID: page.id, url: url.absoluteString, title: title))
            core.drain()
        }
    }
#endif
