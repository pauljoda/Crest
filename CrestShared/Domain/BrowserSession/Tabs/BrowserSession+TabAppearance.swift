import Foundation

extension BrowserSession {
    mutating func updateSelectedTab(
        url: URL?,
        title: String?,
        faviconData: Data? = nil,
        iconAccent: BrowserTabIconAccent? = nil
    ) {
        guard let indices = selectedTabIndices else { return }
        spaces[indices.space].tabs[indices.tab].url = url
        if spaces[indices.space].tabs[indices.tab].iconMode == .automatic {
            if let faviconData, !faviconData.isEmpty {
                spaces[indices.space].tabs[indices.tab].faviconData = faviconData
                spaces[indices.space].tabs[indices.tab].faviconURL = url
                spaces[indices.space].tabs[indices.tab].iconAccent = iconAccent
            }
        }
        if let title, !title.isEmpty {
            spaces[indices.space].tabs[indices.tab].title = title
        }
    }

    /// The named-tab twin of ``updateSelectedTab(url:title:faviconData:iconAccent:)``.
    ///
    /// A Split View card observes its own page whether or not it is the focused
    /// one, so an unfocused card needs the same url/title/favicon write against a
    /// tab that is not `selectedTabID`. The field rules are deliberately
    /// identical — automatic icons only, non-empty favicon data, non-empty title
    /// — because a tab must not record different metadata depending on which
    /// card happened to have focus when its page settled.
    @discardableResult
    mutating func updateTab(
        url: URL?,
        title: String?,
        faviconData: Data? = nil,
        iconAccent: BrowserTabIconAccent? = nil,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: {
                $0.id == tabID
            })
        else { return false }
        spaces[spaceIndex].tabs[tabIndex].url = url
        if spaces[spaceIndex].tabs[tabIndex].iconMode == .automatic {
            if let faviconData, !faviconData.isEmpty {
                spaces[spaceIndex].tabs[tabIndex].faviconData = faviconData
                spaces[spaceIndex].tabs[tabIndex].faviconURL = url
                spaces[spaceIndex].tabs[tabIndex].iconAccent = iconAccent
            }
        }
        if let title, !title.isEmpty {
            spaces[spaceIndex].tabs[tabIndex].title = title
        }
        return true
    }

    /// Names a tab by hand. The observed page title keeps updating underneath,
    /// so clearing the rename returns the tab to whatever the page reports.
    @discardableResult
    mutating func setTabCustomTitle(
        _ title: String?,
        tabID: TabID,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
              let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }) else {
            return false
        }
        let resolvedTitle = BrowserTab.resolvedCustomTitle(title)
        guard spaces[spaceIndex].tabs[tabIndex].customTitle != resolvedTitle else {
            return false
        }
        spaces[spaceIndex].tabs[tabIndex].customTitle = resolvedTitle
        spaces[spaceIndex].tabs[tabIndex].markTitleModified(at: date)
        return true
    }

    @discardableResult
    mutating func setTabEmojiIcon(
        _ emoji: String,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
              let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }),
              !emoji.isEmpty else { return false }
        spaces[spaceIndex].tabs[tabIndex].symbol = BrowserTab.symbol(forEmoji: emoji)
        spaces[spaceIndex].tabs[tabIndex].faviconData = nil
        spaces[spaceIndex].tabs[tabIndex].faviconURL = nil
        spaces[spaceIndex].tabs[tabIndex].iconAccent = nil
        spaces[spaceIndex].tabs[tabIndex].iconMode = .emoji
        return true
    }

    @discardableResult
    mutating func setTabFavicon(
        _ faviconData: Data,
        iconAccent: BrowserTabIconAccent?,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
              let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }),
              !faviconData.isEmpty else { return false }
        spaces[spaceIndex].tabs[tabIndex].symbol = "globe"
        spaces[spaceIndex].tabs[tabIndex].faviconData = faviconData
        spaces[spaceIndex].tabs[tabIndex].faviconURL = spaces[spaceIndex].tabs[tabIndex].url
        spaces[spaceIndex].tabs[tabIndex].iconAccent = iconAccent
        spaces[spaceIndex].tabs[tabIndex].iconMode = .pulled
        return true
    }

    @discardableResult
    mutating func cacheAutomaticTabFavicon(
        _ faviconData: Data,
        iconAccent: BrowserTabIconAccent?,
        url: URL,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
              let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }),
              spaces[spaceIndex].tabs[tabIndex].iconMode == .automatic,
              !faviconData.isEmpty else { return false }
        let currentURL = spaces[spaceIndex].tabs[tabIndex].url
        let normalizedCurrent = currentURL.flatMap(BrowserHistoryURL.normalized) ?? currentURL
        let normalizedCaptured = BrowserHistoryURL.normalized(url) ?? url
        guard normalizedCurrent == normalizedCaptured else { return false }
        spaces[spaceIndex].tabs[tabIndex].symbol = "globe"
        spaces[spaceIndex].tabs[tabIndex].faviconData = faviconData
        spaces[spaceIndex].tabs[tabIndex].faviconURL = url
        spaces[spaceIndex].tabs[tabIndex].iconAccent = iconAccent
        return true
    }

    @discardableResult
    mutating func clearTabIcon(tabID: TabID, in spaceID: SpaceID) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
              let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }) else {
            return false
        }
        spaces[spaceIndex].tabs[tabIndex].symbol = "globe"
        spaces[spaceIndex].tabs[tabIndex].faviconData = nil
        spaces[spaceIndex].tabs[tabIndex].faviconURL = nil
        spaces[spaceIndex].tabs[tabIndex].iconAccent = nil
        spaces[spaceIndex].tabs[tabIndex].iconMode = .automatic
        return true
    }

    @discardableResult
    mutating func replaceTabSavedLocationWithCurrent(
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
              let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }),
              spaces[spaceIndex].tabs[tabIndex].supportsSavedLocationEditing,
              spaces[spaceIndex].tabs[tabIndex].isAwayFromSavedLocation,
              let currentURL = spaces[spaceIndex].tabs[tabIndex].url else {
            return false
        }
        spaces[spaceIndex].tabs[tabIndex].savedURL = currentURL
        return true
    }

    @discardableResult
    mutating func restoreTabSavedLocation(
        tabID: TabID,
        in spaceID: SpaceID
    ) -> URL? {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
              let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }),
              spaces[spaceIndex].tabs[tabIndex].isAwayFromSavedLocation,
              let savedURL = spaces[spaceIndex].tabs[tabIndex].savedSiteURL else {
            return nil
        }
        spaces[spaceIndex].tabs[tabIndex].url = savedURL
        return savedURL
    }

}
