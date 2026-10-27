import Foundation

/// Native page confirmation precedes a semantic close. The operation still
/// commits through the store's authority; a deferred result is not a commit.
@MainActor
protocol BrowserPageDismissalAuthorizing: AnyObject {
    // MARK: - Actions - Dismissal

    func performDismissal(
        of assignments: [BrowserTabRuntimeAssignment],
        in browser: BrowserStore,
        completion: @escaping @MainActor (Bool) -> Void,
        operation: @escaping @MainActor () -> Bool
    ) -> Bool
}

extension BrowserStore {
    // MARK: - Actions - Dismissal

    @discardableResult
    func performPageDismissal(
        of assignments: [BrowserTabRuntimeAssignment],
        completion: @escaping @MainActor (Bool) -> Void = { _ in },
        operation: @escaping @MainActor () -> Bool
    ) -> Bool {
        let checked: @MainActor () -> Bool = { [weak self] in
            guard let self,
                assignments.allSatisfy({ assignment in
                    self.spaceModel(
                        matching: BrowserSpaceRuntimeAssignment(
                            spaceID: assignment.spaceID, profileID: assignment.profileID)
                    )?.tabs.contains(assignment.tabID) == true
                })
            else { return false }
            return operation()
        }
        guard let authorizer = family.pageDismissalAuthorizer else {
            let closed = checked()
            completion(closed)
            return closed
        }
        return authorizer.performDismissal(of: assignments, in: self, completion: completion, operation: checked)
    }
}
