import Foundation

struct BrowserExtensionStoredResourceIdentityPreparer:
    BrowserExtensionStoredResourcePreparing
{
    func prepare(
        resourceURL: URL,
        installation _: BrowserExtensionInstallation
    ) throws -> BrowserExtensionStoredResource {
        BrowserExtensionStoredResource(resourceURL: resourceURL)
    }
}
