import Foundation

/// TRANSITIONAL until S6.6e gives the setup and branding previews a detached
/// read model: the real grid over draft tabs that never reached the core,
/// each drawn as the tab it would be. The previews only look; nothing in them
/// acts.
extension PinnedTabGrid {
    @MainActor
    init(
        drafts: [BrowserTab], assignment: BrowserSpaceRuntimeAssignment, selectedTabID: TabID? = nil,
        capabilities: BrowserInteractionCapabilities = BrowserInteractionCapabilities()
    ) {
        let favicons = FaviconAssets()
        favicons.adopt(
            Dictionary(drafts.compactMap { tab in tab.faviconData.map { (tab.id, $0) } }) { first, _ in first },
            holding: { _ in true })
        self.init(
            tabs: drafts.map { TabStateModel(TabState(draft: $0)) }, favicons: favicons, assignment: assignment,
            selectedTabID: selectedTabID, select: { _ in }, capabilities: capabilities)
    }
}

extension TabState {
    /// A draft tab as the core would publish it, before it has a page: at
    /// home, with no page icon of its own.
    init(draft tab: BrowserTab) {
        self.init(
            id: tab.id, title: tab.title, url: tab.url?.absoluteString,
            nativeContent: tab.nativeContent.map { NativeTabContent(kind: $0.kind, resourceID: $0.resourceID) },
            savedURL: tab.savedURL?.absoluteString, symbol: tab.symbol, faviconURL: tab.faviconURL?.absoluteString,
            iconAccent: tab.iconAccent.map { TabIconAccent(red: $0.red, green: $0.green, blue: $0.blue) },
            storedIconMode: tab.storedIconMode, placement: tab.placement, folderID: tab.folderID,
            splitGroupID: tab.splitGroupID, lastActivatedAt: tab.lastActivatedAt,
            positionModifiedAt: tab.positionModifiedAt, customTitle: tab.customTitle,
            titleModifiedAt: tab.titleModifiedAt, keepsPageLoaded: tab.keepsPageLoaded, iconMode: tab.iconMode,
            displayTitle: tab.displayTitle, isAwayFromSavedAddress: false, pageIconIsCurrent: false)
    }
}
