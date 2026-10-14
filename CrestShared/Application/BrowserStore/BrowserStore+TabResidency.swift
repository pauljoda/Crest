import Foundation

// MARK: - Residency

extension BrowserStore {
    @discardableResult
    func setTabKeepsPageLoaded(
        _ keepsPageLoaded: Bool,
        for id: UUID,
        in spaceID: UUID
    ) -> Bool {
        guard
            setSessionTabResidency(
                keepsPageLoaded,
                tabID: id,
                in: spaceID
            )
        else { return false }
        return true
    }

    @discardableResult
    func setTabKeepsPageLoaded(
        _ keepsPageLoaded: Bool,
        for id: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard spaceModel(matching: assignment)?.tabs.model(id) != nil else { return false }
        return setTabKeepsPageLoaded(
            keepsPageLoaded,
            for: id,
            in: assignment.spaceID
        )
    }
}
