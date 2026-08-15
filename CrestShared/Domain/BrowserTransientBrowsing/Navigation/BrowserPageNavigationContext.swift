import Foundation

struct BrowserPageNavigationContext: Equatable, Sendable {
    let tabID: TabID
    let title: String
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
}
