import Foundation

struct BrowserExtensionStoredResourcePreparationRequest {
    let extensionID: String
    let source: BrowserExtensionInstallationSource?
    let spaceID: SpaceID
    let requestedPermissions: [String]
    /// Mirrors the flag `BrowserExtensionRuntimeContextController` will hand
    /// `BrowserExtensionRuntimeIdentifierPolicy` when it loads this package.
    /// The generated compatibility runtime bakes the base URL in as a literal
    /// and compares `location.href` against it, so the preparer has to reach
    /// the same identity the context will run under.
    var sharesDataStoreWithAnotherContext = false
}

@MainActor
protocol BrowserExtensionStoredResourcePreparing {
    func prepare(
        resourceURL: URL,
        request: BrowserExtensionStoredResourcePreparationRequest
    ) throws -> BrowserExtensionStoredResource
}

extension BrowserExtensionStoredResourcePreparing {
    func prepare(
        resourceURL: URL,
        installation: BrowserExtensionInstallation
    ) throws -> BrowserExtensionStoredResource {
        try prepare(
            resourceURL: resourceURL,
            request: BrowserExtensionStoredResourcePreparationRequest(
                extensionID: installation.id,
                source: installation.source,
                spaceID: installation.spaceID,
                requestedPermissions: installation.requestedPermissions
            )
        )
    }
}
