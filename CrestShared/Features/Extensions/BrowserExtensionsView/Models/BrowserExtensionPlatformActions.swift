@MainActor
struct BrowserExtensionPlatformActions {
    private let openOptionsPageAction: ((String, SpaceID) -> Void)?

    init(
        openOptionsPage: ((String, SpaceID) -> Void)?
    ) {
        openOptionsPageAction = openOptionsPage
    }

    var supportsOptionsPage: Bool {
        openOptionsPageAction != nil
    }

    func openOptionsPage(
        extensionID: String,
        in spaceID: SpaceID
    ) {
        openOptionsPageAction?(extensionID, spaceID)
    }

    static let none = BrowserExtensionPlatformActions(
        openOptionsPage: nil
    )
}
