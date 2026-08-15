import Foundation

struct BrowserTabRuntimeAssignment: Equatable, Hashable, Sendable {
    let tabID: TabID
    let spaceID: SpaceID
    let profileID: UUID
}
