import Foundation

/// Scene restoration carries identities only; the application owns the workspace.
struct BrowserMacWindowRequest: Hashable, Identifiable {
    // MARK: - Static Variables

    /// The initial normal browser window, whose identity stays the same
    /// across launches.
    static let initial = BrowserMacWindowRequest(
        // 3A92C7E8-46F1-4D55-86BB-0F226747F8D1
        id: UUID(
            uuid: (
                0x3A, 0x92, 0xC7, 0xE8,
                0x46, 0xF1,
                0x4D, 0x55,
                0x86, 0xBB,
                0x0F, 0x22, 0x67, 0x47, 0xF8, 0xD1
            )),
        kind: .normal)

    // MARK: - Types

    enum Kind: String, Codable { case normal, temporary }

    // MARK: - Variables

    let id: BrowserWindowID
    let kind: Kind
    var sourceWindowID: BrowserWindowID?
    var sourceAssignment: BrowserSpaceRuntimeAssignment?

    // MARK: - Initializers

    static func normal(sourceWindowID: BrowserWindowID?) -> Self {
        Self(id: BrowserWindowID(), kind: .normal, sourceWindowID: sourceWindowID)
    }

    static func temporary(sourceWindowID: BrowserWindowID?, assignment: BrowserSpaceRuntimeAssignment) -> Self {
        Self(
            id: BrowserWindowID(), kind: .temporary,
            sourceWindowID: sourceWindowID, sourceAssignment: assignment)
    }

    /// The request a normal window kept under `id` reopens with.
    static func reopening(_ id: BrowserWindowID) -> Self {
        id == initial.id ? initial : Self(id: id, kind: .normal)
    }
}

// MARK: - Codable

/// SwiftUI saves a window's request for scene restoration, so its identities
/// keep the stored spelling a build before S6.2 restores.
extension BrowserMacWindowRequest: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case sourceWindowID
        case sourceAssignment
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIdentity(forKey: .id),
            kind: try container.decode(Kind.self, forKey: .kind),
            sourceWindowID: try container.decodeIdentityIfPresent(forKey: .sourceWindowID),
            sourceAssignment: try container.decodeIfPresent(
                BrowserSpaceRuntimeAssignment.self, forKey: .sourceAssignment))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeStoredIdentity(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encodeStoredIdentityIfPresent(sourceWindowID, forKey: .sourceWindowID)
        try container.encodeIfPresent(sourceAssignment, forKey: .sourceAssignment)
    }
}
