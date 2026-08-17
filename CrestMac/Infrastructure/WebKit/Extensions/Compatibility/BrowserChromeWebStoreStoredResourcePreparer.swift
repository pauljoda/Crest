import Foundation

struct BrowserStoreWebExtensionStoredResourcePreparer:
    BrowserExtensionStoredResourcePreparing
{
    private let compatibilityPreparer: BrowserWebExtensionCompatibilityPackagePreparer

    init(fileManager: FileManager = .default) {
        compatibilityPreparer =
            BrowserWebExtensionCompatibilityPackagePreparer(
                fileManager: fileManager
            )
    }

    init(
        compatibilityPreparer:
            BrowserWebExtensionCompatibilityPackagePreparer
    ) {
        self.compatibilityPreparer = compatibilityPreparer
    }

    func prepare(
        resourceURL: URL,
        installation: BrowserExtensionInstallation
    ) throws -> BrowserExtensionStoredResource {
        let supportsCompatibilityPreparation: Bool
        switch installation.source {
        case .chromeWebStore(let source):
            supportsCompatibilityPreparation =
                source.extensionID.rawValue == installation.id
        case .mozillaAddons(let source):
            supportsCompatibilityPreparation =
                source.extensionID.rawValue == installation.id
        case .localPackage(let source):
            supportsCompatibilityPreparation =
                source.extensionID == installation.id
        case .unpackedPackage, .safariWebExtension, nil:
            supportsCompatibilityPreparation = false
        }
        guard supportsCompatibilityPreparation else {
            return BrowserExtensionStoredResource(resourceURL: resourceURL)
        }
        guard
            let preparedPackage =
                try compatibilityPreparer
                .prepareStoredResource(
                    resourceURL,
                    requestedPermissions: installation.requestedPermissions,
                    runtimeIdentity:
                        BrowserExtensionRuntimeIdentifierPolicy
                        .identity(
                            extensionID: installation.id,
                            source: installation.source,
                            spaceID: installation.spaceID
                        )
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

typealias BrowserChromeWebStoreStoredResourcePreparer =
    BrowserStoreWebExtensionStoredResourcePreparer
