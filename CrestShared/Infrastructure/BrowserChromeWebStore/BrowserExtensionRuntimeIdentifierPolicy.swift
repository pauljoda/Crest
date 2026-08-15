import Foundation

enum BrowserExtensionRuntimeIdentifierPolicy {
    static func identifier(
        extensionID: String,
        source: BrowserExtensionInstallationSource?,
        spaceID: SpaceID
    ) -> String {
        if case .chromeWebStore(let chromeSource) = source,
            chromeSource.extensionID.rawValue == extensionID
        {
            return extensionID
        }
        return "\(extensionID).space.\(spaceID.rawValue.uuidString.lowercased())"
    }
}
