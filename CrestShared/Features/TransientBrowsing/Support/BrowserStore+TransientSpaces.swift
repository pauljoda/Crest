import Foundation

extension BrowserStore {
    // MARK: - Actions - Transient Pages

    /// The Spaces of this workspace a transient page may move to or unlock:
    /// none being deleted, and none locked but the request's own.
    func transientSpaces(
        forRequestIn requestSpaceID: UUID,
        isLocked: @MainActor (SpaceModel) -> Bool
    ) -> [SpaceModel] {
        BrowserSidebarAccessPolicy.availableSpaces(in: self).filter {
            $0.id == requestSpaceID || !isLocked($0)
        }
    }
}
