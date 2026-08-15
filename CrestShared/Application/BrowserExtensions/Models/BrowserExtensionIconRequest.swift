struct BrowserExtensionIconRequest: Sendable {

    static let maximumPixelSizeLimit = 512

    let extensionID: String?
    let spaceID: SpaceID
    let payload: BrowserExtensionIconPayload?
    let maximumPixelSize: Int

    var identity: BrowserExtensionIconRequestIdentity {
        BrowserExtensionIconRequestIdentity(
            extensionID: extensionID,
            spaceID: spaceID,
            contentIdentifier: payload?.contentIdentifier,
            maximumPixelSize: maximumPixelSize
        )
    }

    init(
        extensionID: String?,
        spaceID: SpaceID,
        payload: BrowserExtensionIconPayload?,
        maximumPixelSize: Int
    ) {
        self.extensionID = extensionID
        self.spaceID = spaceID
        self.payload = payload
        self.maximumPixelSize = min(
            max(1, maximumPixelSize),
            Self.maximumPixelSizeLimit
        )
    }
}
