import Foundation

struct BrowserTabSections: Equatable, Sendable {
    let pinnedTabs: [BrowserTab]
    let unfiledSavedTabs: [BrowserTab]
    let currentTabs: [BrowserTab]
    private let tabsByFolderID: [FolderID: [BrowserTab]]

    init(tabs: [BrowserTab]) {
        var pinnedTabs: [BrowserTab] = []
        var unfiledSavedTabs: [BrowserTab] = []
        var currentTabs: [BrowserTab] = []
        var tabsByFolderID: [FolderID: [BrowserTab]] = [:]

        pinnedTabs.reserveCapacity(min(tabs.count, BrowserSpace.maximumPinnedTabs))
        currentTabs.reserveCapacity(tabs.count)

        for tab in tabs {
            if let folderID = tab.folderID {
                tabsByFolderID[folderID, default: []].append(tab)
            }
            switch tab.placement {
            case .pinned:
                pinnedTabs.append(tab)
            case .saved:
                if tab.folderID == nil {
                    unfiledSavedTabs.append(tab)
                }
            case .current:
                currentTabs.append(tab)
            }
        }

        self.pinnedTabs = pinnedTabs
        self.unfiledSavedTabs = unfiledSavedTabs
        self.currentTabs = currentTabs
        self.tabsByFolderID = tabsByFolderID
    }

    func tabs(in folderID: FolderID) -> [BrowserTab] {
        tabsByFolderID[folderID] ?? []
    }

    func savedTabs(in folderID: FolderID) -> [BrowserTab] {
        tabs(in: folderID).filter { $0.placement == .saved }
    }

    /// Start Page tabs are uncommitted navigation drafts. They live in the
    /// session for restoration and WebKit ownership, but are not browser tabs
    /// until navigation gives them a URL.
    var sidebarCurrentTabs: [BrowserTab] {
        currentTabs.filter { !$0.isStartPage }
    }
}
