import Foundation

struct BrowserSpaceRuntimeAssignment: Codable, Equatable, Hashable, Sendable {
    let spaceID: SpaceID
    let profileID: UUID

    init(spaceID: SpaceID, profileID: UUID) {
        self.spaceID = spaceID
        self.profileID = profileID
    }

    init(space: BrowserSpace) {
        self.init(spaceID: space.id, profileID: space.profile.id)
    }

    func matches(_ space: BrowserSpace) -> Bool {
        space.id == spaceID && space.profile.id == profileID
    }
}

// MARK: - Identifiable

extension BrowserSpaceRuntimeAssignment: Identifiable {
    var id: Self { self }
}
