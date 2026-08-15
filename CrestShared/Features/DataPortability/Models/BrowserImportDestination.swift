enum BrowserImportDestination: Codable, Equatable, Hashable, Sendable {
    case newSpace
    case existing(SpaceID)
}
