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
        request: BrowserExtensionStoredResourcePreparationRequest
    ) throws -> BrowserExtensionStoredResource {
        let supportsCompatibilityPreparation: Bool
        switch request.source {
        case .chromeWebStore(let source):
            supportsCompatibilityPreparation =
                source.extensionID.rawValue == request.extensionID
        case .mozillaAddons(let source):
            supportsCompatibilityPreparation =
                source.extensionID.rawValue == request.extensionID
        case .localPackage(let source):
            supportsCompatibilityPreparation =
                source.extensionID == request.extensionID
        case .unpackedPackage, nil:
            supportsCompatibilityPreparation = true
        case .safariWebExtension:
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
                    requestedPermissions: request.requestedPermissions,
                    runtimeIdentity:
                        BrowserExtensionRuntimeIdentifierPolicy
                        .identity(
                            extensionID: request.extensionID,
                            source: request.source,
                            spaceID: request.spaceID
                        )
                )
        else {
            return BrowserExtensionStoredResource(resourceURL: resourceURL)
        }
        return BrowserExtensionStoredResource(
            resourceURL: preparedPackage.resourceURL,
            retainedAccess: preparedPackage,
            internalGrantedPermissions:
                preparedPackage.internalGrantedPermissions
        )
    }
}

typealias BrowserChromeWebStoreStoredResourcePreparer =
    BrowserStoreWebExtensionStoredResourcePreparer
