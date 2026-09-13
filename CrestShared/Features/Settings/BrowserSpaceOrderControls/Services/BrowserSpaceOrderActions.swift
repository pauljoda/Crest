import Foundation

@MainActor
struct BrowserSpaceOrderActions {
    let browser: BrowserStore
    let spaceID: SpaceID?

    var canMoveUp: Bool {
        guard let index else { return false }
        return index > browser.session.spaces.startIndex
    }

    var canMoveDown: Bool {
        guard let index else { return false }
        return index < browser.session.spaces.count - 1
    }

    func moveUp() {
        guard let index, index > browser.session.spaces.startIndex else { return }
        browser.moveSpaces(from: IndexSet(integer: index), to: index - 1)
    }

    func moveDown() {
        guard let index, index < browser.session.spaces.count - 1 else { return }
        // The insertion offset precedes removal of the source Space.
        browser.moveSpaces(from: IndexSet(integer: index), to: index + 2)
    }

    private var index: Int? {
        guard let spaceID, !browser.deletingSpaceIDs.contains(spaceID) else { return nil }
        return browser.session.spaces.firstIndex { $0.id == spaceID }
    }
}
