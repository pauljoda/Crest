import Foundation

@MainActor
enum BrowserExtensionsPreviewFixture {
    static let space = BrowserSpace(
        id: SpaceID(
            rawValue: UUID(
                uuid: (
                    0x41, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                    0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
                )
            )
        ),
        profile: BrowsingProfile(
            id: UUID(
                uuid: (
                    0x42, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
                    0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
                )
            )
        ),
        name: "Work",
        symbol: "briefcase.fill",
        accent: .indigo,
        folders: [],
        tabs: [],
        selectedTabID: nil
    )

    static let pool = BrowserExtensionControllerPool(
        packageStore: BrowserExtensionsPreviewExtensionPackageStore(),
        registry: BrowserExtensionRegistry(
            persistence: InMemoryBrowserExtensionRegistryPersistence()
        ),
        usesEphemeralWebKitStorage: true
    )

    static let summary = BrowserExtensionSummary(
        id: "com.example.reading-companion",
        displayName: "Reading Companion",
        version: "1.2.0",
        requestedPermissions: ["tabs", "storage"],
        requestedHosts: ["https://developer.apple.com/*"],
        unsupportedAPIs: [],
        errors: [],
        isEnabled: true,
        isLoaded: true,
        permissionSnapshot: .empty
    )

    static let issue = BrowserExtensionIssuePresentation(
        title: "Limited compatibility",
        message: "This extension uses an API that Crest does not yet support.",
        technicalDetails: ["nativeMessaging is unavailable"]
    )

    static let iconPayload = BrowserExtensionIconPayloadFactory.production
        .payload(
            for: Data(
                base64Encoded:
                    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlO5h8AAAAASUVORK5CYII="
            )
        )

    static var model: BrowserExtensionsModel {
        BrowserExtensionsModel(
            space: space,
            extensionControllerPool: pool
        )
    }

    /// A fixed-clock update model whose schedule can never actually fire: the
    /// injected sleep throws immediately, so a rendered preview cannot start
    /// a background pass.
    static let updateModel = BrowserExtensionUpdateModel(
        preferencesPersistence:
            InMemoryBrowserExtensionUpdatePreferencesPersistence(
                preferences: .default
            ),
        updateMetadataPersistence:
            InMemoryBrowserExtensionUpdateMetadataPersistence(
                lastCheckedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
        checker: BrowserExtensionsPreviewUpdateChecker(),
        applier: BrowserExtensionsPreviewUpdateApplier(),
        now: { Date(timeIntervalSince1970: 1_700_000_000) },
        sleep: { _ in throw CancellationError() }
    )
}
