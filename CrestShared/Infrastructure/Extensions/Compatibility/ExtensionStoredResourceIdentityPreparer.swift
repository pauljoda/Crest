import Foundation

struct BrowserExtensionStoredResourceIdentityPreparer:
    BrowserExtensionStoredResourcePreparing
{
    func prepare(
        resourceURL: URL,
        request _: BrowserExtensionStoredResourcePreparationRequest
    ) async throws -> BrowserExtensionStoredResource {
        BrowserExtensionStoredResource(resourceURL: resourceURL)
    }
}
