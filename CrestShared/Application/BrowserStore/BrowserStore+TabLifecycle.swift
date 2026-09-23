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

    /// Like launch presentation, entering an unloaded Space keeps the
    /// remembered tab intact and does not persist a replacement selection.
    @discardableResult
    func presentStartPageForSpaceEntry() -> TabID? {
        selectOrCreateStartPageDraft(excludingSplitGroups: true)?.tabID
    }

    private func selectOrCreateStartPageDraft(excludingSplitGroups: Bool = false) -> (
        tabID: TabID,
        wasCreated: Bool
    )? {
        guard let space = selectedSpace else { return nil }
        if let draft = space.currentTabs.first(where: {
            $0.isStartPage && (!excludingSplitGroups || space.splitGroup(containing: $0.id) == nil)
        }) {
            guard activateSessionTab(draft.id, in: space.id) else { return nil }
            return (draft.id, false)
        }
        guard
            let tabID = openSessionTab(
                title: BrowserTab.startPageTitle,
                url: nil,
                symbol: BrowserTab.startPageSymbol,
                in: space.id,
                insertingAfter: space.selectedTabID
            )
        else { return nil }
        return (tabID, true)
    }

    @discardableResult
    func openNewTab(url: URL) -> TabID? {
        guard let space = selectedSpace else { return nil }
        let tabID = openSessionTab(
            title: url.host() ?? url.absoluteString,
            url: url,
            in: space.id,
            insertingAfter: space.selectedTabID
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
        let tabID = openSessionTab(
            title: url.host() ?? url.absoluteString,
            url: url,
            in: spaceID,
            insertingAfter: space.selectedTabID,
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
    /// arrives as a nil or empty URL and becomes an `about:blank` tab, because a tab
    /// without a URL is a start page rather than a web page.
    func openPopupTab(url: URL?, in spaceID: SpaceID, selecting: Bool = true) -> BrowserPopupTabRegistration? {
        guard !deletingSpaceIDs.contains(spaceID),
            let space = session.space(id: spaceID),
            let destinationURL = url.flatMap({ $0.absoluteString.isEmpty ? nil : $0 }) ?? URL(string: "about:blank")
        else { return nil }
        guard
            let tabID = openSessionTab(
                title: destinationURL.host() ?? destinationURL.absoluteString,
                url: destinationURL,
                in: spaceID,
                insertingAfter: space.selectedTabID,
                shouldSelect: selecting
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
            openTab: { [weak self] url, spaceID, selecting in
                self?.openPopupTab(url: url, in: spaceID, selecting: selecting)
            },
            closeTab: { [weak self] tabID, spaceID in
                _ = self?.closeTab(tabID, in: spaceID)
            }
        )
    }

    @discardableResult
    func closeTab(_ id: TabID, in spaceID: SpaceID) -> Bool {
        closeTab(id, in: spaceID, resetArchivePlacement: true)
    }

    private func closeTab(_ id: TabID, in spaceID: SpaceID, resetArchivePlacement: Bool) -> Bool {
        guard let space = session.space(id: spaceID),
            space.tabs.contains(where: { $0.id == id }) else { return false }
        let assignment = BrowserTabRuntimeAssignment(tabID: id, spaceID: spaceID, profileID: space.profile.id)
        return performPageDismissal(of: [assignment]) { [weak self] in
            guard let self, let current = self.session.space(id: spaceID) else { return false }
            let fallbackID = current.selectedTabID == id
                ? self.dismissalFallbackTabID(afterDismissing: id, in: current) : nil
            guard self.closeSessionTab(id, in: spaceID, fallbackTabID: fallbackID,
                resetArchivePlacement: resetArchivePlacement) else { return false }
            self.persist(deletionReason: .superseded, scope: .core)
            return true
        }
    }

    @discardableResult
    func openExternalURL(_ url: URL) -> Bool {
        guard BrowserCorePolicy.acceptsExternalURL(url) else { return false }
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
    @discardableResult
    func closeTab(_ id: TabID) -> Bool {
        guard let space = selectedSpace,
            space.currentTabs.contains(where: { $0.id == id }) else { return false }
        return closeTab(id, in: space.id, resetArchivePlacement: false)
    }

    func deleteTab(_ id: TabID, in spaceID: SpaceID) {
        guard let space = session.space(id: spaceID) else { return }
        _ = deleteTab(id, matching: BrowserSpaceRuntimeAssignment(space: space))
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
        guard let space = space(matching: assignment) else { return false }
        let ids = Set(space.currentTabs.map(\.id))
        let tabs = ids.map { BrowserTabRuntimeAssignment(tabID: $0, spaceID: space.id, profileID: space.profile.id) }
        return performPageDismissal(of: tabs) { [weak self] in
            guard let self, let current = self.space(matching: assignment),
                Set(current.currentTabs.map(\.id)) == ids,
                self.clearSessionTabs(in: assignment.spaceID) else { return false }
            self.persist(deletionReason: .superseded, scope: .core)
            return true
        }
    }

    @discardableResult
    func deleteTab(
        _ id: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        let tab = BrowserTabRuntimeAssignment(tabID: id, spaceID: assignment.spaceID, profileID: assignment.profileID)
        return performPageDismissal(of: [tab]) { [weak self] in
            guard let self, self.deleteSessionTab(id, in: assignment.spaceID) else { return false }
            self.persist(deletionReason: .explicitDelete, scope: .core)
            return true
        }
    }

    @discardableResult
    func setTabCustomTitle(
        _ title: String?,
        for id: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard renameSessionTab(title, tabID: id, in: spaceID) else {
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
        guard let normalized = BrowserIconSymbol.normalizedEmoji(emoji),
            setSessionTabIcon("emoji", emoji: normalized, tabID: id, in: spaceID)
        else { return }
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
            let normalized = BrowserIconSymbol.normalizedEmoji(emoji),
            setSessionTabIcon("emoji", emoji: normalized, tabID: id, in: assignment.spaceID)
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
            setSessionTabIcon("pulled", faviconData: faviconData,
                iconAccent: iconAccent, tabID: id, in: spaceID)
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
            setSessionTabIcon("pulled", faviconData: faviconData,
                iconAccent: iconAccent, tabID: id, in: assignment.spaceID)
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
            cacheSessionTabFavicon(faviconData, iconAccent: iconAccent,
                url: url, tabID: id, in: spaceID)
        else { return }
        persist(syncUrgency: .coalesced, scope: .favicon(for: id))
    }

    func clearTabIcon(for id: TabID, in spaceID: SpaceID) {
        guard setSessionTabIcon("automatic", tabID: id, in: spaceID) else { return }
        persist(syncUrgency: .coalesced, scope: .favicon(for: id))
    }

    @discardableResult
    func clearTabIcon(
        for id: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            space.tabs.contains(where: { $0.id == id }),
            setSessionTabIcon("automatic", tabID: id, in: assignment.spaceID)
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
            setSessionSavedLocation("replace", tabID: id, in: spaceID)
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func restoreTabSavedLocation(
        _ id: TabID,
        in spaceID: SpaceID
    ) -> URL? {
        guard setSessionSavedLocation("restore", tabID: id, in: spaceID),
            let url = session.space(id: spaceID)?.tabs.first(where: { $0.id == id })?.url
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
        guard closeTab(tab.id) else { return nil }
        return tab.id
    }

    func navigateSelectedTab(to url: URL) {
        guard let space = selectedSpace, let tabID = space.selectedTabID,
            let observation = observeSessionTab(url: url, title: url.host() ?? url.absoluteString,
                faviconData: nil, iconAccent: nil, tabID: tabID, in: space.id)
        else { return }
        persist(syncUrgency: .coalesced, scope: saveScope(for: observation))
    }

    func updateSelectedTabFromPage(
        url observedURL: URL?,
        title: String?,
        faviconData: Data? = nil,
        iconAccent: BrowserTabIconAccent? = nil
    ) {
        guard let space = selectedSpace, let tabID = space.selectedTabID,
            let observation = observeSessionTab(url: observedURL, title: title,
                faviconData: faviconData, iconAccent: iconAccent, tabID: tabID, in: space.id)
        else { return }
        persist(syncUrgency: .coalesced, scope: saveScope(for: observation))
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
    /// A completed navigation records its visit in the same publication. The
    /// return value reports whether the page metadata changed.
    @discardableResult
    func updateTabFromPage(
        url observedURL: URL?,
        title: String?,
        faviconData: Data? = nil,
        iconAccent: BrowserTabIconAccent? = nil,
        for tabID: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        completedNavigationURL: URL? = nil
    ) -> Bool {
        guard let space = space(matching: assignment) else { return false }
        var scope: BrowserSessionSaveScope?
        if space.tabs.contains(where: { $0.id == tabID }),
            let observation = observeSessionTab(url: observedURL, title: title,
                faviconData: faviconData, iconAccent: iconAccent, tabID: tabID, in: assignment.spaceID)
        {
            scope = saveScope(for: observation)
        }
        let changedMetadata = scope != nil
        if let url = completedNavigationURL {
            if family.executeRecords("history.visit", in: assignment.spaceID,
                arguments: ["url": url.absoluteString, "title": title as Any? ?? NSNull()],
                from: self) {
                scope = scope ?? .history(in: assignment.spaceID)
                scope?.history = .only([assignment.spaceID])
            }
        }
        guard let scope else { return false }
        persist(syncUrgency: .coalesced, scope: scope)
        return changedMetadata
    }

    func updateBackgroundPage(_ update: BrowserBackgroundPageUpdate) {
        updateTabFromPage(
            url: update.url, title: update.title, faviconData: update.faviconData,
            iconAccent: update.iconAccent, for: update.tabID, matching: update.assignment,
            completedNavigationURL: update.completedNavigationURL
        )
    }

    /// A title rewrite touches only the core; an icon the page replaced also
    /// reconciles that tab's favicon bytes. Which of those happened is the
    /// core's answer; turning it into a save scope is this adapter's work.
    private func saveScope(for observation: BrowserTabObservation) -> BrowserSessionSaveScope {
        observation.changedFavicon ? .favicon(for: observation.tabID) : .core
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
            setSessionTabResidency(
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
