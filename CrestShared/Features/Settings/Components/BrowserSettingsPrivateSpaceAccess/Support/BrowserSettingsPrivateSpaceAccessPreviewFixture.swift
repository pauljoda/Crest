import Foundation

@MainActor
enum BrowserSettingsPrivateSpaceAccessPreviewFixture {
    static let space = BrowserSpace(
        id: SpaceID(
            rawValue: UUID(
                uuid: (
                    0x43, 0x52, 0x45, 0x53,
                    0x54, 0x53,
                    0x45, 0x54,
                    0x54, 0x49,
                    0x4E, 0x47, 0x53, 0x50, 0x41, 0x43
                ))
        ),
        profile: BrowsingProfile(
            id: UUID(
                uuid: (
                    0x43, 0x52, 0x45, 0x53,
                    0x54, 0x50,
                    0x52, 0x4F,
                    0x46, 0x49,
                    0x4C, 0x45, 0x53, 0x50, 0x41, 0x43
                ))
        ),
        name: "Private Research",
        symbol: "lock.shield.fill",
        accent: .indigo,
        folders: [],
        tabs: [],
        accessPolicy: .deviceOwnerAuthentication,
        selectedTabID: nil
    )

    static let accessController = BrowserSpaceAccessController(
        authenticator: BrowserSettingsPrivateSpacePreviewAuthenticator()
    )
}
