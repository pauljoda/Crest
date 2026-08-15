import Foundation

struct BrowserCredentialSaveKey: Hashable {
    let spaceID: SpaceID
    let origin: CredentialOrigin
    let normalizedUsername: String

    init(
        candidate: BrowserCredentialSaveCandidate,
        spaceID: SpaceID
    ) {
        self.spaceID = spaceID
        origin = candidate.origin
        normalizedUsername = candidate.username.lowercased()
    }
}
