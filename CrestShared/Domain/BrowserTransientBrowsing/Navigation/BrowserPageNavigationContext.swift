import Foundation

struct BrowserPageNavigationContext: Equatable, Sendable {
    let tabID: TabID
    let title: String
    let customTitle: String?
    let placement: TabPlacement
    let savedURL: URL?
    let iconMode: BrowserTabIconMode
    let spaceAssignment: BrowserSpaceRuntimeAssignment
    let automaticallyOpensPeek: Bool
    let keepsPageLoaded: Bool

    var spaceID: SpaceID { spaceAssignment.spaceID }

    var assignment: BrowserSpaceRuntimeAssignment { spaceAssignment }

    init(
        tab: BrowserTab,
        spaceID: SpaceID,
        profileID: UUID,
        automaticallyOpensPeek: Bool = true
    ) {
        tabID = tab.id
        title = tab.displayTitle
        customTitle = BrowserTab.resolvedCustomTitle(tab.customTitle)
        placement = tab.placement
        savedURL = tab.savedSiteURL
        iconMode = tab.iconMode
        spaceAssignment = BrowserSpaceRuntimeAssignment(
            spaceID: spaceID,
            profileID: profileID
        )
        self.automaticallyOpensPeek = automaticallyOpensPeek
        keepsPageLoaded = tab.keepsPageLoaded
    }

    /// A reader-supplied name always wins. Otherwise a resident page's current
    /// document title is more authoritative than the title last persisted for
    /// the tab, including while that page is playing in another Space.
    func mediaSessionOwnerTitle(observedPageTitle: String?) -> String? {
        customTitle
            ?? BrowserTab.resolvedCustomTitle(observedPageTitle)
            ?? BrowserTab.resolvedCustomTitle(title)
    }
}
