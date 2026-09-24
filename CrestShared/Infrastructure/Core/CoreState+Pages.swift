import Foundation

extension CoreState {
    func apply(_ change: PageOpened) {
        pages[change.page.id] = PageStateModel(change.page)
    }

    /// A page that stays open keeps its object, which notifies only for what
    /// really changed.
    func apply(_ change: PageChanged) {
        if let page = pages[change.page.id] {
            page.update(change.page)
        } else {
            pages[change.page.id] = PageStateModel(change.page)
        }
    }

    func apply(_ change: PageRemoved) {
        pages[change.pageID] = nil
    }

    /// A recorded navigation changes no page: the session changes before it
    /// carry what it recorded, and `CrestCore` tells the engines' observers.
    func apply(_ change: NavigationRecorded) {}
}
