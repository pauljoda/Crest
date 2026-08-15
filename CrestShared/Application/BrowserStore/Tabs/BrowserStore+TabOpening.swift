import Foundation

extension BrowserStore {
    @discardableResult
    func openNewTab() -> TabID? {
        guard selectedSpace != nil else { return nil }
        if let draft = selectedSpace?.currentTabs.first(where: \.isStartPage) {
            session.selectTab(draft.id)
            persist(syncUrgency: .coalesced, scope: .core)
            return draft.id
        }
        let tabID = session.openTab(
            title: BrowserTab.startPageTitle,
            url: nil,
            symbol: BrowserTab.startPageSymbol
        )
        persist(scope: .core)
        return tabID
    }

    @discardableResult
    func openNewTab(url: URL) -> TabID? {
        guard let space = selectedSpace else { return nil }
        let tabID = session.openTab(
            title: url.host() ?? url.absoluteString,
            url: url,
            in: space.id,
            requestedIndex: BrowserTabInsertionPolicy.requestedIndex(
                after: space.selectedTabID,
                in: space
            )
        )
        persist(scope: .core)
        return tabID
    }

    @discardableResult
    func openNewTab(url: URL, in spaceID: SpaceID) -> TabID? {
        openNewTab(url: url, in: spaceID, selecting: true)
    }

    @discardableResult
    func openNewTab(
        url: URL,
        in spaceID: SpaceID,
        selecting: Bool
    ) -> TabID? {
        guard !deletingSpaceIDs.contains(spaceID),
            let space = session.space(id: spaceID)
        else { return nil }
        let requestedIndex = BrowserTabInsertionPolicy.requestedIndex(
            after: space.selectedTabID,
            in: space
        )
        if selecting {
            session.selectSpace(spaceID)
        }
        let tabID = session.openTab(
            title: url.host() ?? url.absoluteString,
            url: url,
            in: spaceID,
            requestedIndex: requestedIndex,
            shouldSelect: selecting
        )
        persist(scope: .core)
        return tabID
    }

    @discardableResult
    func openNewTab(
        url: URL,
        matching assignment: BrowserSpaceRuntimeAssignment,
        selecting: Bool = true
    ) -> TabID? {
        guard space(matching: assignment) != nil else { return nil }
        return openNewTab(
            url: url,
            in: assignment.spaceID,
            selecting: selecting
        )
    }

    /// Registers the tab that hosts a web-content popup. WebKit is still inside
    /// `createWebViewWith`, so this has to answer synchronously with both the tab
    /// and its Space: the page pool builds the adopting page from them without
    /// consulting session state itself. `window.open()` without a destination
    /// arrives as a nil URL and becomes an `about:blank` tab, because a tab
    /// without a URL is a start page rather than a web page.
    func openPopupTab(url: URL?, in spaceID: SpaceID) -> BrowserPopupTabRegistration? {
        guard !deletingSpaceIDs.contains(spaceID),
            let space = session.space(id: spaceID),
            let destinationURL = url ?? URL(string: "about:blank")
        else { return nil }
        let requestedIndex = BrowserTabInsertionPolicy.requestedIndex(
            after: space.selectedTabID,
            in: space
        )
        session.selectSpace(spaceID)
        guard
            let tabID = session.openTab(
                title: destinationURL.host() ?? destinationURL.absoluteString,
                url: destinationURL,
                in: spaceID,
                requestedIndex: requestedIndex,
                shouldSelect: true
            ),
            let updatedSpace = session.space(id: spaceID),
            let tab = updatedSpace.tabs.first(where: { $0.id == tabID })
        else { return nil }
        persist(scope: .core)
        return BrowserPopupTabRegistration(tab: tab, space: updatedSpace)
    }

    /// Tab-level popup operations for a page pool. `window.close()` reaches
    /// `closeTab` and archives the popup's tab exactly like the close control in
    /// the tab list does.
    var popupTabHost: BrowserPopupTabHost {
        BrowserPopupTabHost(
            openTab: { [weak self] url, spaceID in
                self?.openPopupTab(url: url, in: spaceID)
            },
            closeTab: { [weak self] tabID, spaceID in
                _ = self?.closeTab(tabID, in: spaceID)
            }
        )
    }

    @discardableResult
    func openExtensionTab(
        url: URL?,
        in spaceID: SpaceID,
        pinned: Bool,
        requestedIndex: Int?,
        shouldSelect: Bool
    ) -> TabID? {
        let title = url?.host() ?? url?.absoluteString ?? BrowserTab.startPageTitle
        guard
            let tabID = session.openTab(
                title: title,
                url: url,
                symbol: url == nil ? BrowserTab.startPageSymbol : "globe",
                in: spaceID,
                placement: pinned ? .pinned : .current,
                requestedIndex: requestedIndex,
                shouldSelect: shouldSelect
            )
        else {
            return nil
        }
        persist(scope: .core)
        return tabID
    }

    @discardableResult
    func activateExtensionTab(_ id: TabID, in spaceID: SpaceID) -> Bool {
        guard session.activateTab(id, in: spaceID) else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func closeExtensionTab(_ id: TabID, in spaceID: SpaceID) -> Bool {
        closeTab(id, in: spaceID)
    }

    @discardableResult
    func closeTab(_ id: TabID, in spaceID: SpaceID) -> Bool {
        guard let space = session.space(id: spaceID),
            space.tabs.contains(where: { $0.id == id })
        else { return false }
        let fallbackID = space.selectedTabID == id
            ? dismissalFallbackTabID(afterDismissing: id, in: space)
            : nil
        guard
            session.closeExtensionTab(
                id,
                in: spaceID,
                fallbackTabID: fallbackID
            )
        else { return false }
        persist(deletionReason: .superseded, scope: .core)
        return true
    }

    @discardableResult
    func loadExtensionURL(_ url: URL, in tabID: TabID, spaceID: SpaceID) -> Bool {
        guard session.updateExtensionTab(tabID, in: spaceID, url: url) else {
            return false
        }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func setExtensionTabPinned(
        _ pinned: Bool,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard
            session.setExtensionTabPinned(
                pinned,
                tabID: tabID,
                in: spaceID
            )
        else {
            return false
        }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func duplicateExtensionTab(
        _ id: TabID,
        in spaceID: SpaceID,
        pinned: Bool,
        requestedIndex: Int?,
        shouldSelect: Bool
    ) -> TabID? {
        guard
            let duplicateID = session.duplicateTab(
                id,
                in: spaceID,
                placement: pinned ? .pinned : .current,
                requestedIndex: requestedIndex,
                shouldSelect: shouldSelect
            )
        else {
            return nil
        }
        persist(scope: .favicon(for: duplicateID))
        return duplicateID
    }

    @discardableResult
    func openExternalURL(_ url: URL) -> Bool {
        guard BrowserExternalURLPolicy.accepts(url) else { return false }
        if selectedTab?.isStartPage == true {
            navigateSelectedTab(to: url)
        } else {
            openNewTab(url: url)
        }
        return true
    }

}
