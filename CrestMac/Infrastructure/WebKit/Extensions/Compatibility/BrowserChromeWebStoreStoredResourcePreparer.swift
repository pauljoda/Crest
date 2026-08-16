import Foundation

struct BrowserChromeWebStoreStoredResourcePreparer:
    BrowserExtensionStoredResourcePreparing
{
    private let compatibilityPreparer: BrowserChromeWebStoreCompatibilityPackagePreparer

    init(fileManager: FileManager = .default) {
        compatibilityPreparer =
            BrowserChromeWebStoreCompatibilityPackagePreparer(
                fileManager: fileManager
            )
    }

    init(
        compatibilityPreparer:
            BrowserChromeWebStoreCompatibilityPackagePreparer
    ) {
        self.compatibilityPreparer = compatibilityPreparer
    }

    func prepare(
        resourceURL: URL,
        installation: BrowserExtensionInstallation
    ) throws -> BrowserExtensionStoredResource {
        guard case .chromeWebStore(let source) = installation.source,
            source.extensionID.rawValue == installation.id
        else {
            return BrowserExtensionStoredResource(resourceURL: resourceURL)
        }
        guard
            let preparedPackage =
                try compatibilityPreparer
                .prepareStoredResource(
                    resourceURL,
                    requestedPermissions: installation.requestedPermissions
                )
        else {
            return BrowserExtensionStoredResource(resourceURL: resourceURL)
        }
        return BrowserExtensionStoredResource(
            resourceURL: preparedPackage.resourceURL,
            retainedAccess: preparedPackage
        )
    }
}
