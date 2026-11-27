import Foundation

// MARK: - Opening

extension BrowserStore {
    /// Opens the new tab the person asked for: a Start Page where the app's
    /// preferences put a new tab.
    @discardableResult
    func openNewTab() -> UUID? {
        showStartPage(outsideSplits: false, placesAsNewTab: true)
    }

    /// Presents the Start Page before the person chooses a restored tab.
    ///
    /// Launch presentation is intentionally runtime-only. The durable session
    /// keeps its restored selection, so merely opening and closing Crest does
    /// not turn the Start Page draft into the next "last active tab."
    @discardableResult
    func presentStartPageForLaunch() -> UUID? {
        showStartPage(outsideSplits: false)
    }

    /// Like launch presentation, entering an unloaded Space keeps the
    /// remembered tab intact and does not persist a replacement selection.
    @discardableResult
    func presentStartPageForSpaceEntry() -> UUID? {
        showStartPage(outsideSplits: true)
    }

    /// Shows a Start Page in the Space this window shows, which the core
    /// chooses or opens, and answers it. With `placesAsNewTab` a new one goes
    /// where the app's preferences put a new tab, which may be the folder the
    /// shown tab sits in.
    private func showStartPage(outsideSplits: Bool, placesAsNewTab: Bool = false) -> UUID? {
        guard let space = shownSpace else { return nil }
        let opening = ShowStartPage(
            workspaceID: family.workspaceID, windowID: windowID, spaceID: space.id, tabID: UUID(),
            outsideSplits: outsideSplits, placesAsNewTab: placesAsNewTab)
        guard family.perform(opening, from: self) != nil else { return nil }
        return selectedTabID(in: space.id)
    }

    @discardableResult
    func openNewTab(url: URL) -> UUID? {
        guard let space = shownSpace else { return nil }
        return openSessionTab(.page(url), in: space.id, insertingAfter: selectedTabID(in: space.id))
    }

    @discardableResult
    func openNewTab(url: URL, in spaceID: UUID) -> UUID? {
        openNewTab(url: url, in: spaceID, selecting: true)
    }

    /// Opens `url` in a new tab after the one shown in Space `spaceID`, or,
    /// when `placesAsNewTab`, as for a link the person opened, where the app's
    /// preferences put a new tab, which may be the end of the folder that tab
    /// sits in, a saved one too when `savesInSavedFolder`, as for an address
    /// typed for a new tab.
    @discardableResult
    func openNewTab(
        url: URL,
        in spaceID: UUID,
        selecting: Bool,
        placesAsNewTab: Bool = false,
        savesInSavedFolder: Bool = false
    ) -> UUID? {
        guard !isDeleting(spaceID), spaceModel(spaceID) != nil else { return nil }
        return openSessionTab(
            .page(url), in: spaceID, insertingAfter: selectedTabID(in: spaceID), shouldSelect: selecting,
            placesAsNewTab: placesAsNewTab, savesInSavedFolder: savesInSavedFolder)
    }

    @discardableResult
    func openNewTab(
        url: URL,
        matching assignment: BrowserSpaceRuntimeAssignment,
        selecting: Bool = true
    ) -> UUID? {
        guard spaceModel(matching: assignment) != nil else { return nil }
        return openNewTab(
            url: url,
            in: assignment.spaceID,
            selecting: selecting
        )
    }

    /// Opens `url` in a new tab behind the one shown in Space `spaceID`, as a
    /// person asked from a link or the palette, and confirms it: in a saved
    /// folder the shown tab sits in only when `savesInSavedFolder`, as for an
    /// address typed in the palette. Tabs opened for anyone else, such as an
    /// agent, use `openNewTab`.
    @discardableResult
    func openBackgroundTab(url: URL, in spaceID: UUID, savesInSavedFolder: Bool = false) -> UUID? {
        guard
            let tabID = openNewTab(
                url: url, in: spaceID, selecting: false, placesAsNewTab: true, savesInSavedFolder: savesInSavedFolder)
        else { return nil }
        interactionObserver?.browserDidOpenBackgroundTab()
        return tabID
    }

    /// Opens `url` in a new tab of Space `spaceID` for a modified link,
    /// selected when `selecting`, and answers the tab with its Space.
    func openModifiedLink(_ url: URL, in spaceID: UUID, selecting: Bool) -> BrowserModifiedLinkRegistration? {
        let opened =
            selecting
            ? openNewTab(url: url, in: spaceID, selecting: true, placesAsNewTab: true)
            : openBackgroundTab(url: url, in: spaceID)
        guard let tabID = opened,
            let space = spaceModel(spaceID),
            let tab = space.shownTab(tabID)
        else { return nil }
        return BrowserModifiedLinkRegistration(tab: tab, space: space)
    }

    /// Closes an open tab once its page agrees to go, which the core archives.
    /// A saved or pinned tab's page is put away by `BrowserDurableTabCloseAction`,
    /// which retires the page first, so this path leaves it alone.
    @discardableResult
    func closeTab(_ id: UUID, in spaceID: UUID) -> Bool {
        guard let space = spaceModel(spaceID), let tab = space.shownTab(id), !tab.placement.isDurable
        else { return false }
        let assignment = BrowserTabRuntimeAssignment(tabID: id, spaceID: spaceID, profileID: space.profileID)
        // The core asks the tab's page whether it may go before it closes the tab.
        return performPageDismissal(of: [assignment]) { [weak self] in
            guard let self, self.spaceModel(spaceID) != nil else { return false }
            return self.closeSessionTab(id, in: spaceID)
        }
    }

    /// Opens an address another app handed Crest in the Space this window
    /// shows, as `openAddress` does.
    @discardableResult
    func openExternalURL(_ url: URL) -> Bool {
        guard ExternalWebLink.accepts(url), let space = shownSpace else { return false }
        return openAddress(url, in: space.id)
    }

    /// Opens `url` in a Space this window shows: the Start Page on show there
    /// takes it, or a new tab opens it, which the core decides. With
    /// `placesAsNewTab`, as for a new tab the person typed in the palette, that
    /// tab goes where the app's preferences put a new tab.
    @discardableResult
    func openAddress(_ url: URL, in spaceID: UUID, placesAsNewTab: Bool = false) -> Bool {
        let opening = OpenAddress(
            workspaceID: family.workspaceID, windowID: windowID, spaceID: spaceID, tabID: UUID(),
            address: url.absoluteString, placesAsNewTab: placesAsNewTab)
        return family.perform(opening, from: self) != nil
    }

}

// MARK: - Metadata

extension BrowserStore {
    /// The open tabs of `space` that clearing puts away, as the sidebar offers
    /// Clear from the read model: all of them, or, keeping the shown tab, all
    /// but the tab this window shows there and the rest of its split. Clearing
    /// itself asks the core (see `ClearedTabs`).
    func clearedTabIDs(of space: SpaceModel, keepingShownTab: Bool) -> Set<UUID> {
        let open = space.tabs.models.filter { $0.placement == .current }
        guard keepingShownTab, let shown = selectedTabID(in: space.id).flatMap({ space.tabs.model($0) }) else {
            return Set(open.map(\.id))
        }
        let kept = { (tab: TabStateModel) in
            tab.id == shown.id || (shown.splitGroupID != nil && tab.splitGroupID == shown.splitGroupID)
        }
        return Set(open.filter { !kept($0) }.map(\.id))
    }

    @discardableResult
    func closeTab(_ id: UUID) -> Bool {
        guard let space = shownSpace, space.shownTab(id)?.placement == .current else { return false }
        return closeTab(id, in: space.id)
    }

    func deleteTab(_ id: UUID, in spaceID: UUID) {
        guard let space = spaceModel(spaceID) else { return }
        _ = deleteTab(id, matching: BrowserSpaceRuntimeAssignment(space: space))
    }

    @discardableResult
    func closeTab(
        _ id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment)?.shownTab(id) != nil else { return false }
        return closeTab(id, in: assignment.spaceID)
    }

    /// Archives the Space's open tabs, but for the tab this window shows there
    /// when `keepingShownTab`, and offers this window's Undo for the clear.
    @discardableResult
    func clearCurrentTabs(
        matching assignment: BrowserSpaceRuntimeAssignment,
        keepingShownTab: Bool
    ) -> Bool {
        guard spaceModel(matching: assignment) != nil else { return false }
        let clearing = ClearedTabs(
            workspaceID: family.workspaceID, windowID: windowID, spaceID: assignment.spaceID,
            keepsShownTab: keepingShownTab)
        guard let ids = try? core.query(clearing).tabIDs, !ids.isEmpty else { return false }
        let tabs = ids.map {
            BrowserTabRuntimeAssignment(tabID: $0, spaceID: assignment.spaceID, profileID: assignment.profileID)
        }
        return performPageDismissal(of: tabs) { [weak self] in
            // A tab that opened or went while its pages were asked was not
            // asked itself, so the Space stays as it is.
            guard let self, self.spaceModel(matching: assignment) != nil,
                Set((try? self.core.query(clearing).tabIDs) ?? []) == Set(ids),
                let clearID = self.clearSessionTabs(in: assignment.spaceID, keepingShownTab: keepingShownTab)
            else { return false }
            self.clearUndo?.offerUndo(
                of: BrowserTabsClearing(id: clearID, space: assignment, keepsShownTab: keepingShownTab))
            return true
        }
    }

    /// Clears the open tabs of the Space this window shows, unless it is
    /// locked, keeping the shown tab when `keepingShownTab`.
    @discardableResult
    func clearShownSpaceTabs(accessController: BrowserSpaceAccessController, keepingShownTab: Bool) -> Bool {
        guard let space = shownSpace, !accessController.isLocked(space) else { return false }
        return clearCurrentTabs(matching: BrowserSpaceRuntimeAssignment(space: space), keepingShownTab: keepingShownTab)
    }

    @discardableResult
    func deleteTab(
        _ id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        let tab = BrowserTabRuntimeAssignment(tabID: id, spaceID: assignment.spaceID, profileID: assignment.profileID)
        return performPageDismissal(of: [tab]) { [weak self] in
            guard let self, self.deleteSessionTab(id, in: assignment.spaceID) else { return false }
            return true
        }
    }

    @discardableResult
    func setTabCustomTitle(
        _ title: String?,
        for id: UUID,
        in spaceID: UUID
    ) -> Bool {
        guard renameSessionTab(title, tabID: id, in: spaceID) else {
            return false
        }
        return true
    }

    @discardableResult
    func setTabCustomTitle(
        _ title: String?,
        for id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment)?.shownTab(id) != nil else { return false }
        return setTabCustomTitle(title, for: id, in: assignment.spaceID)
    }

    /// Gives the tab `emoji` as its icon, which the core refuses when its
    /// first character does not present as an emoji.
    func setTabEmojiIcon(_ emoji: String, for id: UUID, in spaceID: UUID) {
        _ = setSessionTabIcon(.emoji, emoji: emoji, tabID: id, in: spaceID)
    }

    @discardableResult
    func setTabEmojiIcon(
        _ emoji: String,
        for id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment)?.shownTab(id) != nil else { return false }
        return setSessionTabIcon(.emoji, emoji: emoji, tabID: id, in: assignment.spaceID)
    }

    func setTabFavicon(
        _ faviconData: Data,
        iconAccent: BrowserTabIconAccent?,
        for id: UUID,
        in spaceID: UUID
    ) {
        guard
            setSessionTabIcon(
                .pulled, faviconData: faviconData,
                iconAccent: iconAccent, tabID: id, in: spaceID)
        else { return }
    }

    @discardableResult
    func setTabFavicon(
        _ faviconData: Data,
        iconAccent: BrowserTabIconAccent?,
        for id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment)?.shownTab(id) != nil else { return false }
        return setSessionTabIcon(
            .pulled, faviconData: faviconData, iconAccent: iconAccent, tabID: id, in: assignment.spaceID)
    }

    func clearTabIcon(for id: UUID, in spaceID: UUID) {
        guard setSessionTabIcon(.automatic, tabID: id, in: spaceID) else { return }
    }

    @discardableResult
    func clearTabIcon(
        for id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment)?.shownTab(id) != nil else { return false }
        return setSessionTabIcon(.automatic, tabID: id, in: assignment.spaceID)
    }

    @discardableResult
    func replaceTabSavedLocationWithCurrent(
        _ id: UUID,
        in spaceID: UUID
    ) -> Bool {
        replaceSessionSavedAddress(tabID: id, in: spaceID)
    }

    @discardableResult
    func restoreTabSavedLocation(
        _ id: UUID,
        in spaceID: UUID
    ) -> URL? {
        guard returnSessionTabToSavedAddress(tabID: id, in: spaceID) else { return nil }
        return spaceModel(spaceID)?.shownTab(id)?.address
    }

    /// Archives the tab this window shows, where the core allows it.
    @discardableResult
    func archiveSelectedTab() -> UUID? {
        guard allows(.archiveTab), let space = shownSpace, let tab = shownTab, closeTab(tab.id, in: space.id) else {
            return nil
        }
        return tab.id
    }

    /// Gives the selected tab `url` to load when it shows a native view or the
    /// Start Page, so a page can open for it. An existing web page stays at its
    /// accepted location until its engine reports the new navigation, which
    /// the core records.
    /// Gives the selected tab, while it shows a native view or the Start
    /// Page, the address `input` names by its Space's rules, so a page can
    /// open for it. False when it changed nothing: the tab shows a web page,
    /// the input was blank, or a rule refused it.
    @discardableResult
    func navigateSelectedTab(to input: String) -> Bool {
        guard let space = shownSpace, let tab = shownTab, !tab.surface.showsPage else { return false }
        return family.send(
            NavigateTab(
                workspaceID: family.workspaceID, spaceID: space.id, tabID: tab.id, input: input),
            from: self)
    }

}

// MARK: - Residency

extension BrowserStore {
    @discardableResult
    func setTabKeepsPageLoaded(
        _ keepsPageLoaded: Bool,
        for id: UUID,
        in spaceID: UUID
    ) -> Bool {
        guard
            setSessionTabResidency(
                keepsPageLoaded,
                tabID: id,
                in: spaceID
            )
        else { return false }
        return true
    }

    @discardableResult
    func setTabKeepsPageLoaded(
        _ keepsPageLoaded: Bool,
        for id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment)?.shownTab(id) != nil else { return false }
        return setTabKeepsPageLoaded(
            keepsPageLoaded,
            for: id,
            in: assignment.spaceID
        )
    }
}
