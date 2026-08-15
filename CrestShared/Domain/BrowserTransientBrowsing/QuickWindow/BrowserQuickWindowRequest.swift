import Foundation

struct BrowserQuickWindowRequest: Codable, Hashable, Identifiable, Sendable {
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
