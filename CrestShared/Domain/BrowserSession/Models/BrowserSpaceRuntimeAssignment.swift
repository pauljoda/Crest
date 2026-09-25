import Foundation

struct BrowserSpaceRuntimeAssignment: Equatable, Hashable, Sendable {
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

// MARK: - Codable

/// Scene restoration keeps an assignment inside a window's request, so its
/// Space keeps the stored identity spelling.
extension BrowserSpaceRuntimeAssignment: Codable {
    private enum CodingKeys: String, CodingKey {
        case spaceID
        case profileID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            spaceID: try container.decodeIdentity(forKey: .spaceID),
            profileID: try container.decode(UUID.self, forKey: .profileID))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeStoredIdentity(spaceID, forKey: .spaceID)
        try container.encode(profileID, forKey: .profileID)
    }
}

// MARK: - Identifiable

extension BrowserSpaceRuntimeAssignment: Identifiable {
    var id: Self { self }
}
