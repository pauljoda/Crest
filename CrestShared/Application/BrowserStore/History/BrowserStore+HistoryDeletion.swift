import Foundation

/// Space-exact targeted history removal.
///
/// Every entry point takes a ``BrowserSpaceRuntimeAssignment`` rather than a
/// bare `SpaceID`, matching the rest of the deletion surface: a Space that was
/// replaced or is mid-deletion must not have its successor's history erased by
/// a request captured against the old one.
extension BrowserStore {
    @discardableResult
    func deleteHistory(
        for url: URL,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil,
            session.removeHistory(for: url, in: assignment.spaceID)
        else {
            return false
        }
        persist(
            deletionReason: .explicitDelete,
            scope: .history(in: assignment.spaceID)
        )
        return true
    }

    @discardableResult
    func deleteHistory(
        from startDate: Date,
        until endDate: Date,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil,
            session.removeHistory(
                from: startDate,
                until: endDate,
                in: assignment.spaceID
            )
        else {
            return false
        }
        persist(
            deletionReason: .explicitDelete,
            scope: .history(in: assignment.spaceID)
        )
        return true
    }
}
