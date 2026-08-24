import Foundation

// MARK: - Opening

extension BrowserStore {
    @discardableResult
    func openNewTab() -> TabID? {
        guard let result = selectOrCreateStartPageDraft() else { return nil }
        if result.wasCreated {
            persist(scope: .core)
        } else {
            persist(syncUrgency: .coalesced, scope: .core)
        }
        return result.tabID
    }

    /// Presents the Start Page before the person chooses a restored tab.
    ///
    /// Launch presentation is intentionally runtime-only. The durable session
    /// keeps its restored selection, so merely opening and closing Crest does
    /// not turn the Start Page draft into the next "last active tab."
    @discardableResult
    func presentStartPageForLaunch() -> TabID? {
        selectOrCreateStartPageDraft()?.tabID
    }

    private func selectOrCreateStartPageDraft() -> (
        tabID: TabID,
        wasCreated: Bool
    )? {
        guard let space = selectedSpace else { return nil }
        if let draft = space.currentTabs.first(where: \.isStartPage) {
            session.selectTab(draft.id)
            return (draft.id, false)
        }
        guard let tabID = session.openTab(
            title: BrowserTab.startPageTitle,
            url: nil,
            symbol: BrowserTab.startPageSymbol,
            in: space.id,
            requestedIndex: BrowserTabInsertionPolicy.requestedIndex(
                after: space.selectedTabID,
                in: space
            )
        ) else { return nil }
        return (tabID, true)
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
        let fallbackID =
            space.selectedTabID == id
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

// MARK: - Metadata

extension BrowserStore {
    func closeTab(_ id: TabID) {
        guard let space = selectedSpace,
            space.currentTabs.contains(where: { $0.id == id })
        else { return }
        let fallbackID =
            space.selectedTabID == id
            ? dismissalFallbackTabID(afterDismissing: id, in: space)
            : nil
        session.closeTab(id, fallbackTabID: fallbackID)
        persist(deletionReason: .superseded, scope: .core)
    }

    func deleteTab(_ id: TabID, in spaceID: SpaceID) {
        guard session.deleteTab(id, in: spaceID) else { return }
        persist(deletionReason: .explicitDelete, scope: .core)
    }

    @discardableResult
    func closeTab(
        _ id: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            space.tabs.contains(where: { $0.id == id })
        else { return false }
        return closeTab(id, in: assignment.spaceID)
    }

    @discardableResult
    func clearCurrentTabs(
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil,
            session.clearCurrentTabs(in: assignment.spaceID)
        else { return false }
        persist(deletionReason: .superseded, scope: .core)
        return true
    }

    @discardableResult
    func deleteTab(
        _ id: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            space.tabs.contains(where: { $0.id == id }),
            session.deleteTab(id, in: assignment.spaceID)
        else { return false }
        persist(deletionReason: .explicitDelete, scope: .core)
        return true
    }

    @discardableResult
    func setTabCustomTitle(
        _ title: String?,
        for id: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard session.setTabCustomTitle(title, tabID: id, in: spaceID) else {
            return false
        }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func setTabCustomTitle(
        _ title: String?,
        for id: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            space.tabs.contains(where: { $0.id == id })
        else { return false }
        return setTabCustomTitle(title, for: id, in: assignment.spaceID)
    }

    func setTabEmojiIcon(_ emoji: String, for id: TabID, in spaceID: SpaceID) {
        guard session.setTabEmojiIcon(emoji, tabID: id, in: spaceID) else { return }
        persist(syncUrgency: .coalesced, scope: .favicon(for: id))
    }

    @discardableResult
    func setTabEmojiIcon(
        _ emoji: String,
        for id: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            space.tabs.contains(where: { $0.id == id }),
            session.setTabEmojiIcon(
                emoji,
                tabID: id,
                in: assignment.spaceID
            )
        else { return false }
        persist(syncUrgency: .coalesced, scope: .favicon(for: id))
        return true
    }

    func setTabFavicon(
        _ faviconData: Data,
        iconAccent: BrowserTabIconAccent?,
        for id: TabID,
        in spaceID: SpaceID
    ) {
        guard
            session.setTabFavicon(
                faviconData,
                iconAccent: iconAccent,
                tabID: id,
                in: spaceID
            )
        else { return }
        persist(syncUrgency: .coalesced, scope: .favicon(for: id))
    }

    @discardableResult
    func setTabFavicon(
        _ faviconData: Data,
        iconAccent: BrowserTabIconAccent?,
        for id: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            space.tabs.contains(where: { $0.id == id }),
            session.setTabFavicon(
                faviconData,
                iconAccent: iconAccent,
                tabID: id,
                in: assignment.spaceID
            )
        else { return false }
        persist(syncUrgency: .coalesced, scope: .favicon(for: id))
        return true
    }

    func cacheAutomaticTabFavicon(
        _ faviconData: Data,
        iconAccent: BrowserTabIconAccent?,
        url: URL,
        for id: TabID,
        in spaceID: SpaceID
    ) {
        guard
            session.cacheAutomaticTabFavicon(
                faviconData,
                iconAccent: iconAccent,
                url: url,
                tabID: id,
                in: spaceID
            )
        else { return }
        persist(syncUrgency: .coalesced, scope: .favicon(for: id))
    }

    func clearTabIcon(for id: TabID, in spaceID: SpaceID) {
        guard session.clearTabIcon(tabID: id, in: spaceID) else { return }
        persist(syncUrgency: .coalesced, scope: .favicon(for: id))
    }

    @discardableResult
    func clearTabIcon(
        for id: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            space.tabs.contains(where: { $0.id == id }),
            session.clearTabIcon(tabID: id, in: assignment.spaceID)
        else { return false }
        persist(syncUrgency: .coalesced, scope: .favicon(for: id))
        return true
    }

    @discardableResult
    func replaceTabSavedLocationWithCurrent(
        _ id: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard
            session.replaceTabSavedLocationWithCurrent(
                tabID: id,
                in: spaceID
            )
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func restoreTabSavedLocation(
        _ id: TabID,
        in spaceID: SpaceID
    ) -> URL? {
        guard
            let url = session.restoreTabSavedLocation(
                tabID: id,
                in: spaceID
            )
        else { return nil }
        persist(syncUrgency: .coalesced, scope: .core)
        return url
    }

    @discardableResult
    func archiveSelectedTab() -> TabID? {
        guard let tab = selectedTab,
            tab.placement == .current,
            !tab.isStartPage
        else { return nil }
        closeTab(tab.id)
        return tab.id
    }

    func navigateSelectedTab(to url: URL) {
        session.updateSelectedTab(
            url: url,
            title: url.host() ?? url.absoluteString,
            faviconData: nil,
            iconAccent: nil
        )
        persist(syncUrgency: .coalesced, scope: .core)
    }

    func updateSelectedTabFromPage(
        url observedURL: URL?,
        title: String?,
        faviconData: Data? = nil,
        iconAccent: BrowserTabIconAccent? = nil
    ) {
        let resolvedURL = observedURL ?? selectedTab?.url
        let updatesAutomaticIcon =
            selectedTab?.iconMode == .automatic
            && (faviconData != selectedTab?.faviconData
                || iconAccent != selectedTab?.iconAccent)
        guard
            resolvedURL != selectedTab?.url
                || BrowserStoredStringPolicy.normalized(title)
                    != BrowserStoredStringPolicy.normalized(selectedTab?.title)
                || updatesAutomaticIcon
        else { return }
        // The hot path: a page that rewrites `document.title` reaches here on
        // every mutation. Only an icon change may touch the favicon store, so a
        // title change rewrites the core alone.
        let iconTabID = updatesAutomaticIcon ? selectedTab?.id : nil
        session.updateSelectedTab(
            url: resolvedURL,
            title: title,
            faviconData: faviconData,
            iconAccent: iconAccent
        )
        persist(
            syncUrgency: .coalesced,
            scope: iconTabID.map(BrowserSessionSaveScope.favicon(for:)) ?? .core
        )
    }

    /// The per-tab twin of ``updateSelectedTabFromPage(url:title:faviconData:iconAccent:)``.
    ///
    /// A Split View card presents a live page for a tab that may not be the
    /// selected one, and that page reports the same url, title, and favicon the
    /// focused card's page does. Without this, an unfocused card would browse
    /// with a sidebar row frozen at whatever it said when the card appeared.
    ///
    /// Everything the selected-tab path decides is decided the same way here —
    /// the change gate, the automatic-icon identity rules, and the save scope
    /// that keeps a title rewrite off the favicon store. The one addition is the
    /// Space assignment: a card binds a tab it did not select, so the write is
    /// confirmed against the Space and profile the caller is drawing before it
    /// touches the session. A stale card mid-Space-switch writes nothing.
    @discardableResult
    func updateTabFromPage(
        url observedURL: URL?,
        title: String?,
        faviconData: Data? = nil,
        iconAccent: BrowserTabIconAccent? = nil,
        for tabID: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            let tab = space.tabs.first(where: { $0.id == tabID })
        else { return false }
        let resolvedURL = observedURL ?? tab.url
        let updatesAutomaticIcon =
            tab.iconMode == .automatic
            && (faviconData != tab.faviconData || iconAccent != tab.iconAccent)
        guard
            resolvedURL != tab.url
                || BrowserStoredStringPolicy.normalized(title)
                    != BrowserStoredStringPolicy.normalized(tab.title)
                || updatesAutomaticIcon
        else { return false }
        guard
            session.updateTab(
                url: resolvedURL,
                title: title,
                faviconData: faviconData,
                iconAccent: iconAccent,
                tabID: tabID,
                in: assignment.spaceID
            )
        else { return false }
        persist(
            syncUrgency: .coalesced,
            scope: updatesAutomaticIcon ? .favicon(for: tabID) : .core
        )
        return true
    }

}

// MARK: - Residency

extension BrowserStore {
    @discardableResult
    func setTabKeepsPageLoaded(
        _ keepsPageLoaded: Bool,
        for id: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard
            session.setTabKeepsPageLoaded(
                keepsPageLoaded,
                tabID: id,
                in: spaceID
            )
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func setTabKeepsPageLoaded(
        _ keepsPageLoaded: Bool,
        for id: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            space.tabs.contains(where: { $0.id == id })
        else { return false }
        return setTabKeepsPageLoaded(
            keepsPageLoaded,
            for: id,
            in: assignment.spaceID
        )
    }
}
