import Foundation

struct BrowserSpaceRuntimeAssignment: Equatable, Hashable, Sendable {
    let spaceID: UUID
    let profileID: UUID
}

extension BrowserSpaceRuntimeAssignment {
    // MARK: - Initializers

    /// Where a Space of the read model lives: its identity and profile.
    @MainActor
    init(space: SpaceModel) {
        self.init(spaceID: space.id, profileID: space.profileID)
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

// MARK: - Pages

extension Dictionary where Key == BrowserSpaceRuntimeAssignment {
    /// Moves what is kept for each of `spaces` from the profile it browsed
    /// with to the one it browses with now, as when it joins or leaves a
    /// group, so its page follows it instead of being built again.
    @MainActor
    mutating func follow(_ spaces: [SpaceModel]) {
        for space in spaces {
            let key = BrowserSpaceRuntimeAssignment(space: space)
            guard self[key] == nil, let previous = keys.first(where: { $0.spaceID == space.id }) else { continue }
            self[key] = removeValue(forKey: previous)
        }
    }
}
