import Foundation

extension BrowserStore {
    func closeTab(_ id: TabID) {
        guard let space = selectedSpace,
            space.currentTabs.contains(where: { $0.id == id })
        else { return }
        let fallbackID = space.selectedTabID == id
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
