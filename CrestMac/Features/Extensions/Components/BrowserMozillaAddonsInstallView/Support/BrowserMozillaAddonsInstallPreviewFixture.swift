import Foundation

@MainActor
enum BrowserMozillaAddonsInstallPreviewFixture {
    static let spaceID = SpaceID(rawValue: uuid(0x71))
    static let spaceName = "Research"

    static let candidate: BrowserMozillaAddonsCandidate = {
        guard
            let url = URL(
                string:
                    "https://addons.mozilla.org/en-US/firefox/addon/reading-focus/"
            ),
            let item = BrowserMozillaAddonsItem(url: url),
            let extensionID = BrowserMozillaExtensionID(
                "reading-focus@example.test"
            )
        else {
            preconditionFailure("The fixed Firefox Add-ons preview URL is invalid.")
        }
        let source = BrowserMozillaAddonsSource(
            slug: item.slug,
            extensionID: extensionID,
            storeURL: item.storeURL,
            version: "1.0.0",
            xpiSHA256Hex: String(repeating: "a", count: 64)
        )
        return BrowserMozillaAddonsCandidate(
            item: item,
            source: source,
            verifiedPackage: BrowserVerifiedXPIPackage(
                extensionID: extensionID,
                archiveData: Data(),
                xpiSHA256Hex: source.xpiSHA256Hex
            ),
            displayName: "Reading Focus",
            version: "1.0.0",
            displayDescription:
                "A Mozilla-signed add-on for keeping long-form reading distraction free.",
            requestedPermissions: ["storage", "tabs"],
            requestedHosts: ["https://developer.apple.com/*"],
            errors: ["Unsupported manifest entry: sidebar_action"],
            iconPayload: nil,
            hasOptionsPage: true,
            hasCommands: true,
            isMozillaRecommended: true,
            nativeMessagingCapability: .available
        )
    }()

    static func makeSession() -> BrowserMozillaAddonsInstallSession {
        BrowserMozillaAddonsInstallSession(
            spaceID: spaceID,
            spaceName: spaceName
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x4D,
                0x4F, 0x5A,
                0x41, 0x44,
                0x44, 0x4F, 0x4E, 0x53, 0x50, finalByte
            ))
    }
}
