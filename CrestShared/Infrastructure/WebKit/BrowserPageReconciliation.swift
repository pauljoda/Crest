import Foundation

/// A single session traversal supplies both runtime reconciliation and archive
/// retention. The platform still controls how pages are released and presented.
@MainActor
struct BrowserPageReconciliation {
    let validAssignments: Set<BrowserTabRuntimeAssignment>
    let invalidTabIDs: Set<TabID>
    let tabIDsToArchive: Set<TabID>
    let navigationContexts: [(page: BrowserPlatformPage, tab: BrowserTab)]
    let retainedTabIDsByProfileID: [UUID: Set<TabID>]

    init(
        session: BrowserSession,
        residentPages: some Sequence<(TabID, BrowserPlatformPage)>
    ) {
        var tabsByID: [TabID: (tab: BrowserTab, assignment: BrowserTabRuntimeAssignment)] = [:]
        var archivedAssignments: [TabID: BrowserSpaceRuntimeAssignment] = [:]
        var keptTabIDsByProfileID: [UUID: Set<TabID>] = [:]
        for space in session.spaces {
            let spaceAssignment = BrowserSpaceRuntimeAssignment(space: space)
            for tab in space.tabs {
                let assignment = BrowserTabRuntimeAssignment(
                    tabID: tab.id, spaceID: space.id, profileID: space.profile.id
                )
                precondition(tabsByID[tab.id] == nil)
                tabsByID[tab.id] = (tab, assignment)
            }
            for archivedTab in space.archivedTabs {
                precondition(archivedAssignments[archivedTab.id] == nil)
                archivedAssignments[archivedTab.id] = spaceAssignment
            }
            keptTabIDsByProfileID[space.profile.id, default: []].formUnion(
                space.tabs.map(\.id) + space.archivedTabs.map(\.tab.id)
            )
        }
        validAssignments = Set(tabsByID.values.map(\.assignment))
        retainedTabIDsByProfileID = keptTabIDsByProfileID

        var invalid: Set<TabID> = []
        var toArchive: Set<TabID> = []
        var contexts: [(page: BrowserPlatformPage, tab: BrowserTab)] = []
        for (tabID, page) in residentPages {
            if let entry = tabsByID[tabID], entry.tab.nativeContent == nil,
                entry.assignment.spaceID == page.spaceID,
                entry.assignment.profileID == page.profileID
            {
                contexts.append((page, entry.tab))
                continue
            }
            invalid.insert(tabID)
            if let assignment = archivedAssignments[tabID],
                assignment.spaceID == page.spaceID,
                assignment.profileID == page.profileID
            {
                toArchive.insert(tabID)
            }
        }
        invalidTabIDs = invalid
        tabIDsToArchive = toArchive
        navigationContexts = contexts
    }
}
