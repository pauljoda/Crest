import Foundation

struct BrowserExtensionStoredResourcePreparationRequest {
    let extensionID: String
    let source: BrowserExtensionInstallationSource?
    let spaceID: SpaceID
    let requestedPermissions: [String]
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
