import Foundation

extension CoreState {
    func apply(_ change: PageOpened) {
        publish(PageStateModel(change.page), forKey: change.page.id, into: \.pagesStorage, as: \.pages)
    }

    /// A page that stays open keeps its object, which notifies only for what
    /// really changed.
    func apply(_ change: PageChanged) {
        if let page = pages[change.page.id] {
            page.update(change.page)
        } else {
            publish(PageStateModel(change.page), forKey: change.page.id, into: \.pagesStorage, as: \.pages)
        }
    }

    func apply(_ change: PageRemoved) {
        publish(nil, forKey: change.pageID, into: \.pagesStorage, as: \.pages)
    }

    /// A recorded navigation changes no page: the session changes before it
    /// carry what it recorded, and `CrestCore` tells the engines' observers.
    func apply(_ change: NavigationRecorded) {}
}
