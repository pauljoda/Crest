import Foundation

struct MobileBrowserRootSelectionSnapshot: Equatable, Sendable {
    let sessionRevision: Int
    let selectedSpaceID: SpaceID
    let selectedProfileID: UUID?
    let assignment: BrowserTabRuntimeAssignment?
}
