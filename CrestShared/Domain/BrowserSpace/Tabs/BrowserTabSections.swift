import Foundation

struct BrowserTabSections: Equatable, Sendable {
    let pinnedTabs: [BrowserTab]
    let unfiledSavedTabs: [BrowserTab]
    let currentTabs: [BrowserTab]
    private let savedTabsByFolderID: [FolderID: [BrowserTab]]

    init(tabs: [BrowserTab]) {
        var pinnedTabs: [BrowserTab] = []
        var unfiledSavedTabs: [BrowserTab] = []
        var currentTabs: [BrowserTab] = []
        var savedTabsByFolderID: [FolderID: [BrowserTab]] = [:]

        pinnedTabs.reserveCapacity(min(tabs.count, BrowserSpace.maximumPinnedTabs))
        currentTabs.reserveCapacity(tabs.count)

        for tab in tabs {
            switch tab.placement {
            case .pinned:
                pinnedTabs.append(tab)
            case .saved:
                if let folderID = tab.folderID {
                    savedTabsByFolderID[folderID, default: []].append(tab)
                } else {
                    unfiledSavedTabs.append(tab)
                }
            case .current:
                currentTabs.append(tab)
            }
        }

        self.pinnedTabs = pinnedTabs
        self.unfiledSavedTabs = unfiledSavedTabs
        self.currentTabs = currentTabs
        self.savedTabsByFolderID = savedTabsByFolderID
    }

    func savedTabs(in folderID: FolderID) -> [BrowserTab] {
        savedTabsByFolderID[folderID] ?? []
    }

    /// Start Page tabs are uncommitted navigation drafts. They live in the
    /// session for restoration and WebKit ownership, but are not browser tabs
    /// until navigation gives them a URL.
    var sidebarCurrentTabs: [BrowserTab] {
        currentTabs.filter { !$0.isStartPage }
    }
}
