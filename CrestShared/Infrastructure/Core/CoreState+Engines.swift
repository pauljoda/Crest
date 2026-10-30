import Foundation

extension CoreState {
    // MARK: - Actions - Capabilities

    /// Whether the device offers `capability` anywhere a person can find a
    /// feature, such as a menu or a settings page: the default engine or an
    /// engine a page is open on supports it, or no engine has registered yet.
    /// Extension management remains available for an installed engine even
    /// before it starts; opening that feature explicitly starts its runtime.
    /// Whether a page can use it is its own engine's answer.
    func offers(_ capability: EngineCapability) -> Bool {
        engines?.offered.contains(capability) ?? true
    }

    /// Whether the engine new pages open on supports `capability`, which
    /// answers for a window before it shows a page. Every capability, until
    /// an engine registers.
    func defaultEngineSupports(_ capability: EngineCapability) -> Bool {
        guard let engines else { return true }
        return engines.engines.first(where: \.isDefault)?.capabilities.contains(capability) == true
    }

    // MARK: - Actions - Badges

    /// The engine whose badge the tab's icon wears: the one its page runs on,
    /// when the core badges that engine's pages. Nil for a tab without a page
    /// its engine holds or is making, and on a device where every page runs
    /// on one engine, which reads no page at all.
    func engineBadge(forTab tabID: UUID) -> EngineKind? {
        guard let badged = engines?.badged, !badged.isEmpty, let page = enginePage(ofTab: tabID) else { return nil }
        return badged.contains(page.engine) ? page.engine : nil
    }

    // MARK: - Actions - Pages by tab

    /// The tab's page that its engine holds or is making, or nil. Reading it
    /// observes which pages are open and the tab's own pages, not every page.
    func enginePage(ofTab tabID: UUID) -> PageStateModel? {
        let pages = self.pages
        return pageIDsByTab[tabID]?.lazy.compactMap { pages[$0] }
            .first { $0.tabID == tabID && $0.phase.holdsEnginePage }
    }

    /// Moves page `pageID` in the index from the tab it belonged to, if any,
    /// to the one it belongs to now, if any.
    func indexPage(_ pageID: UUID, from oldTabID: UUID?, to newTabID: UUID?) {
        guard oldTabID != newTabID else { return }
        if let oldTabID {
            pageIDsByTab[oldTabID]?.remove(pageID)
            if pageIDsByTab[oldTabID]?.isEmpty == true { pageIDsByTab[oldTabID] = nil }
        }
        if let newTabID { pageIDsByTab[newTabID, default: []].insert(pageID) }
    }
}
