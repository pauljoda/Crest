import Foundation

/// Moves a Space one place in the workspace, or among the Sub-Spaces on its group's page.
@MainActor
struct BrowserSpaceOrderActions {
    let browser: BrowserStore
    let spaceID: UUID?
    var withinGroup = false

    var canMoveUp: Bool { neighbour(by: -1) != nil }

    var canMoveDown: Bool { neighbour(by: 1) != nil }

    func moveUp() {
        guard let spaceID, let target = neighbour(by: -1) else { return }
        browser.move(spaceID, to: target.id)
    }

    func moveDown() {
        guard let spaceID, let target = neighbour(by: 1) else { return }
        browser.move(spaceID, to: target.id)
    }

    private func neighbour(by step: Int) -> SpaceModel? {
        guard let spaceID, let space = browser.spaceModel(spaceID) else { return nil }
        let spaces = withinGroup ? browser.groupMembers(of: space).filter(browser.isSubSpace) : browser.availableSpaces
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }),
            spaces.indices.contains(index + step)
        else { return nil }
        return spaces[index + step]
    }
}
