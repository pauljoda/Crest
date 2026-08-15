import Foundation

extension BrowserStore {
    func space(
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> BrowserSpace? {
        guard !deletingSpaceIDs.contains(assignment.spaceID),
            let space = session.space(id: assignment.spaceID),
            assignment.matches(space)
        else { return nil }
        return space
    }

    func selectSpace(_ id: SpaceID) {
        guard id != session.selectedSpaceID,
            !deletingSpaceIDs.contains(id),
            session.space(id: id) != nil
        else { return }
        session.selectSpace(id)
        persist(syncUrgency: .coalesced, scope: .core)
    }

    @discardableResult
    func selectAdjacentSpace(_ direction: BrowserSpaceSwipeDirection) -> SpaceID? {
        let spaces = session.spaces.filter {
            !deletingSpaceIDs.contains($0.id)
        }
        guard spaces.count > 1,
            let currentIndex = spaces.firstIndex(where: { $0.id == session.selectedSpaceID })
        else {
            return nil
        }
        let nextIndex: Int
        switch direction {
        case .previous:
            nextIndex = (currentIndex - 1 + spaces.count) % spaces.count
        case .next:
            nextIndex = (currentIndex + 1) % spaces.count
        }
        let nextID = spaces[nextIndex].id
        selectSpace(nextID)
        return nextID
    }

    func selectTab(_ id: TabID) {
        guard selectedSpace != nil else { return }
        session.selectTab(id)
        persist(syncUrgency: .coalesced, scope: .core)
    }

    @discardableResult
    func selectDismissalFallback(afterDismissing id: TabID) -> TabID? {
        guard let space = selectedSpace else { return nil }
        let fallbackID = dismissalFallbackTabID(
            afterDismissing: id,
            in: space
        )
        if let fallbackID {
            session.selectTab(fallbackID)
        } else {
            session.clearTabSelection(in: space.id)
        }
        persist(syncUrgency: .coalesced, scope: .core)
        return fallbackID
    }

    @discardableResult
    func selectAdjacentTab(offset: Int) -> TabID? {
        guard let tabs = selectedSpace?.tabs,
            !tabs.isEmpty,
            let selectedID = selectedTab?.id,
            let selectedIndex = tabs.firstIndex(where: { $0.id == selectedID })
        else {
            return nil
        }
        let count = tabs.count
        let wrappedIndex = (selectedIndex + offset % count + count) % count
        let nextID = tabs[wrappedIndex].id
        selectTab(nextID)
        return nextID
    }

    func dismissalFallbackTabID(
        afterDismissing id: TabID,
        in space: BrowserSpace
    ) -> TabID? {
        tabSelectionHistory.fallbackTabID(
            afterDismissing: id,
            in: space.id,
            availableTabIDs: Set(space.tabs.map(\.id))
        )
    }
}
