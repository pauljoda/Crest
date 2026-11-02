import Foundation

/// Moves a Space one place up or down the workspace's order. A group moves as
/// one: moving its primary moves past a whole neighbouring group, and a
/// Sub-Space moves only among the Sub-Spaces of its group.
@MainActor
struct BrowserSpaceOrderActions {
    let browser: BrowserStore
    let spaceID: UUID?

    var canMoveUp: Bool { moved(by: -1) != nil }

    var canMoveDown: Bool { moved(by: 1) != nil }

    func moveUp() {
        guard let order = moved(by: -1) else { return }
        browser.orderSpaces(order)
    }

    func moveDown() {
        guard let order = moved(by: 1) else { return }
        browser.orderSpaces(order)
    }

    /// The order with the Space moved one place by `step`, or nil when it
    /// cannot move that way: past the end, or a Sub-Space past its primary.
    private func moved(by step: Int) -> [UUID]? {
        guard let spaceID, !browser.isDeleting(spaceID) else { return nil }
        var groups = browser.spaceGroups.map { $0.map(\.id) }
        guard let group = groups.firstIndex(where: { $0.contains(spaceID) }),
            let member = groups[group].firstIndex(of: spaceID)
        else { return nil }
        if member > 0 {
            let target = member + step
            guard groups[group].indices.contains(target), target > 0 else { return nil }
            groups[group].swapAt(member, target)
        } else {
            let target = group + step
            guard groups.indices.contains(target) else { return nil }
            groups.swapAt(group, target)
        }
        return groups.flatMap { $0 } + browser.spaceModels.map(\.id).filter(browser.isDeleting)
    }
}
