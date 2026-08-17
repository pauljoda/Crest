import Foundation

struct MobileBrowserRootLockSnapshot: Equatable, Sendable {
    let sessionRevision: Int
    let selectedSpaceID: SpaceID
    let selectedProfileID: UUID?
    let isLocked: Bool
    let presentation: MobileBrowserPresentation
}

struct MobileBrowserRootSelectionSnapshot: Equatable, Sendable {
    let sessionRevision: Int
    let selectedSpaceID: SpaceID
    let selectedProfileID: UUID?
    let assignment: BrowserTabRuntimeAssignment?
}
