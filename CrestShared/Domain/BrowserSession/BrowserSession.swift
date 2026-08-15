import Foundation

struct BrowserSession: Codable, Equatable, Sendable {
    var spaces: [BrowserSpace]
    var selectedSpaceID: SpaceID
    var defaultSpaceID: SpaceID? = nil
    var disposableSeedMarker: UUID? = nil
}
