import Foundation

extension CoreState {
    func apply(_ change: PageOpened) {
        pages[change.page.id] = change.page
    }

    func apply(_ change: PageChanged) {
        pages[change.page.id] = change.page
    }

    func apply(_ change: PageRemoved) {
        pages[change.pageID] = nil
    }

    /// A recorded navigation changes no page: the session changes before it
    /// carry what it recorded, and `CrestCore` tells the engines' observers.
    func apply(_ change: NavigationRecorded) {}
}
