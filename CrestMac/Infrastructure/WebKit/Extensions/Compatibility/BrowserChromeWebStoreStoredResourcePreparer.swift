import Foundation

struct BrowserStoreWebExtensionStoredResourcePreparer:
    BrowserExtensionStoredResourcePreparing
{
    private let compatibilityPreparer: BrowserWebExtensionCompatibilityPackagePreparer

    init(
        fileManager: FileManager = .default,
        enablesConsoleCapture: Bool = false
    ) {
        compatibilityPreparer =
            BrowserWebExtensionCompatibilityPackagePreparer(
                fileManager: fileManager,
                enablesConsoleCapture: enablesConsoleCapture
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
    ) async throws -> BrowserExtensionStoredResource {
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
        let identity = BrowserExtensionRuntimeIdentifierPolicy.identity(
            extensionID: request.extensionID, source: request.source, spaceID: request.spaceID,
            sharesDataStoreWithAnotherContext: request.sharesDataStoreWithAnotherContext)
        // Archive, file and script preparation has no WebKit objects. Keep its
        // synchronous work and publication lock away from the UI executor.
        let preparation = Task.detached(priority: .userInitiated) { [compatibilityPreparer] in
            try Task.checkCancellation()
            return try compatibilityPreparer.prepareStoredResource(
                resourceURL, requestedPermissions: request.requestedPermissions, runtimeIdentity: identity)
        }
        let package = try await withTaskCancellationHandler {
            let result = try await preparation.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            preparation.cancel()
        }
        guard let preparedPackage = package
        else {
            return BrowserExtensionStoredResource(resourceURL: resourceURL)
        }
        return BrowserExtensionStoredResource(
            resourceURL: preparedPackage.resourceURL,
            retainedAccess: preparedPackage,
            internalGrantedPermissions:
                preparedPackage.internalGrantedPermissions,
            capabilityBrokerGrantedPermissions:
                preparedPackage.capabilityBrokerGrantedPermissions,
            allowsInternalCapabilityBroker:
                preparedPackage.allowsInternalCapabilityBroker
        )
    }
}

typealias BrowserChromeWebStoreStoredResourcePreparer =
    BrowserStoreWebExtensionStoredResourcePreparer
