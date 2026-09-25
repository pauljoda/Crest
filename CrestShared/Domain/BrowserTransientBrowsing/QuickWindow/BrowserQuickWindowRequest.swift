import Foundation

struct BrowserQuickWindowRequest: Hashable, Identifiable, Sendable {
    private static let emptyLookupURL: URL = {
        var components = URLComponents()
        components.scheme = "crest"
        components.host = "quick-window"
        return components.url ?? URL(fileURLWithPath: "/")
    }()

    let id: UUID
    var url: URL
    let spaceAssignment: BrowserSpaceRuntimeAssignment
    let targetWindowID: BrowserWindowID?
    let sourcePresentation: BrowserPeekSourcePresentation?

    var spaceID: SpaceID { spaceAssignment.spaceID }

    var assignment: BrowserSpaceRuntimeAssignment {
        spaceAssignment
    }

    init(
        id: UUID = UUID(),
        url: URL,
        spaceAssignment: BrowserSpaceRuntimeAssignment,
        targetWindowID: BrowserWindowID? = nil,
        sourcePresentation: BrowserPeekSourcePresentation? = nil
    ) {
        self.id = id
        self.url = url
        self.spaceAssignment = spaceAssignment
        self.targetWindowID = targetWindowID
        self.sourcePresentation = sourcePresentation
    }

    static func empty(
        id: UUID = UUID(),
        spaceAssignment: BrowserSpaceRuntimeAssignment,
        targetWindowID: BrowserWindowID? = nil
    ) -> BrowserQuickWindowRequest {
        BrowserQuickWindowRequest(
            id: id,
            url: emptyLookupURL,
            spaceAssignment: spaceAssignment,
            targetWindowID: targetWindowID
        )
    }

    var initialURL: URL? {
        url == Self.emptyLookupURL ? nil : url
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs.initialURL, rhs.initialURL) {
        case (.some(let lhsURL), .some(let rhsURL)):
            lhs.assignment == rhs.assignment && lhsURL == rhsURL
        case (.none, .none):
            lhs.id == rhs.id
        default:
            false
        }
    }

    func hash(into hasher: inout Hasher) {
        if let initialURL {
            hasher.combine(assignment)
            hasher.combine(initialURL)
        } else {
            hasher.combine(id)
        }
    }
}

// MARK: - Codable

/// SwiftUI saves a Quick Window's request for scene restoration, so the window
/// it targets keeps the stored identity spelling a build before S6.2 restores.
extension BrowserQuickWindowRequest: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case url
        case spaceAssignment
        case targetWindowID
        case sourcePresentation
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            url: try container.decode(URL.self, forKey: .url),
            spaceAssignment: try container.decode(BrowserSpaceRuntimeAssignment.self, forKey: .spaceAssignment),
            targetWindowID: try container.decodeIdentityIfPresent(forKey: .targetWindowID),
            sourcePresentation: try container.decodeIfPresent(
                BrowserPeekSourcePresentation.self, forKey: .sourcePresentation))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        try container.encode(spaceAssignment, forKey: .spaceAssignment)
        try container.encodeStoredIdentityIfPresent(targetWindowID, forKey: .targetWindowID)
        try container.encodeIfPresent(sourcePresentation, forKey: .sourcePresentation)
    }
}
