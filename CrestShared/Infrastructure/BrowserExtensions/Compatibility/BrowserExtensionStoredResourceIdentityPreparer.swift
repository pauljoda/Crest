import Foundation

struct BrowserExtensionStoredResourceIdentityPreparer:
    BrowserExtensionStoredResourcePreparing
{
    func prepare(
        resourceURL: URL,
        request _: BrowserExtensionStoredResourcePreparationRequest
    ) throws -> BrowserExtensionStoredResource {
        BrowserExtensionStoredResource(resourceURL: resourceURL)
    }
}
