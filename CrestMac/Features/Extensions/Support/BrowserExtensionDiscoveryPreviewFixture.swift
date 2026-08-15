import Foundation

@MainActor
enum BrowserExtensionDiscoveryPreviewFixture {
    static let candidate = BrowserSafariWebExtensionCandidate(
        source: BrowserSafariWebExtensionSource(
            applicationBookmark: Data(),
            applicationBundleIdentifier: "com.example.reader",
            extensionBundleIdentifier: "com.example.reader.extension",
            relativeBundlePath: "Contents/PlugIns/Reader.appex",
            developerTeamIdentifier: "EXAMPLETEAM"
        ),
        applicationDisplayName: "Reader",
        displayName: "Reader Tools",
        version: "2.0",
        displayDescription: "Focused reading tools for the current page.",
        requestedPermissions: ["tabs", "storage"],
        requestedHosts: ["https://developer.apple.com/*"],
        errors: [],
        iconPayload: BrowserExtensionsPreviewFixture.iconPayload,
        hasOptionsPage: true,
        hasCommands: false,
        hasContentModificationRules: false
    )

    static let item = BrowserExtensionDiscoveryItem(candidate: candidate)

    static var model: BrowserExtensionDiscoveryModel {
        BrowserExtensionDiscoveryModel(
            extensionsModel: BrowserExtensionsPreviewFixture.model
        )
    }
}
