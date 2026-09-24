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
}
