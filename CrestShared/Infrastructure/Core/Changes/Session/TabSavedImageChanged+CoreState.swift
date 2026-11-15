import Foundation

extension TabSavedImageChanged {
    @MainActor func apply(to state: CoreState) {
        if state.workspaces[workspaceID]?.holdsOpen(tabID: tabID) == true {
            switch change {
            case .keep: state.favicons.keepSavedImage(of: tabID, for: faviconURL)
            case .restore: state.favicons.wearSavedImage(of: tabID, for: faviconURL)
            }
        }
        state.touch(workspaceID)
    }
}
