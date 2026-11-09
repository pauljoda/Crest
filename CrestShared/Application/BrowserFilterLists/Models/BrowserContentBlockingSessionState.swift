import Foundation

/// The content blocking each Space of a workspace applies: the device's, the
/// same in every Space.
struct BrowserContentBlockingSessionState: Equatable, Sendable {
    let policiesBySpaceID: [UUID: ContentBlockingPolicy]

    init(policiesBySpaceID: [UUID: ContentBlockingPolicy]) {
        self.policiesBySpaceID = policiesBySpaceID
    }

    /// The device's `policy` for each Space of `workspace` in the read model.
    @MainActor
    init(workspace: WorkspaceModel?, policy: ContentBlockingPolicy) {
        self.init(
            policiesBySpaceID: Dictionary(
                uniqueKeysWithValues: (workspace?.spaces.models ?? []).map { ($0.id, policy) }))
    }
}
