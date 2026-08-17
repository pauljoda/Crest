enum BrowserImportDestination: Codable, Equatable, Hashable, Sendable {
    case newSpace
    case existing(SpaceID)
}

enum BrowserImportDestinationKey: Hashable {
    case existing(SpaceID)
    case new(SpaceID)
}
