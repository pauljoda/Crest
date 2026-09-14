import Foundation

/// Scene restoration carries identities only; the application owns the workspace.
struct BrowserMacWindowRequest: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case normal, temporary }

    let id: BrowserWindowID
    let kind: Kind
    var sourceWindowID: BrowserWindowID?
    var sourceAssignment: BrowserSpaceRuntimeAssignment?

    static let initial = BrowserMacWindowRequest(id: .main, kind: .normal)

    static func normal(sourceWindowID: BrowserWindowID?) -> Self {
        Self(id: BrowserWindowID(), kind: .normal, sourceWindowID: sourceWindowID)
    }

    static func temporary(sourceWindowID: BrowserWindowID?, assignment: BrowserSpaceRuntimeAssignment) -> Self {
        Self(
            id: BrowserWindowID(), kind: .temporary,
            sourceWindowID: sourceWindowID, sourceAssignment: assignment)
    }
}
