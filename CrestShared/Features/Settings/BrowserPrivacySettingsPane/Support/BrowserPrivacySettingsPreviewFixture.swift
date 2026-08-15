import Foundation

@MainActor
enum BrowserPrivacySettingsPreviewFixture {
    static let linkSettings = BrowserLinkSettingsPreviewFixture()
    static let space = linkSettings.primarySpace
    static let record = BrowserSitePermissionRecord(
        id: UUID(
            uuid: (
                0x51, 0, 0, 0, 0, 0, 0x40, 0,
                0x80, 0, 0, 0, 0, 0, 0, 0x01
            )
        ),
        spaceID: space.id,
        origin: BrowserSiteOrigin(
            scheme: "https",
            host: "camera.example",
            port: 443
        ),
        permission: .camera,
        decision: .grantPersistently,
        modifiedAt: Date(timeIntervalSince1970: 0)
    )
    static let permissionCenter = BrowserSitePermissionCenter(
        persistence: InMemoryBrowserSitePermissionPersistence(
            records: [record]
        )
    )
}
