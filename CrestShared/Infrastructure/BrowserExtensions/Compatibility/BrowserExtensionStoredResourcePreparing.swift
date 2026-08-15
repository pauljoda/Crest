import Foundation

@MainActor
protocol BrowserExtensionStoredResourcePreparing {
    func prepare(
        resourceURL: URL,
        installation: BrowserExtensionInstallation
    ) throws -> BrowserExtensionStoredResource
}
