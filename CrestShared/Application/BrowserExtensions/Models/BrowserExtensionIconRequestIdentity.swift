struct BrowserExtensionIconRequestIdentity: Hashable, Sendable {
    let extensionID: String?
    let spaceID: SpaceID
    let contentIdentifier: BrowserExtensionIconContentIdentifier?
    let maximumPixelSize: Int
}
