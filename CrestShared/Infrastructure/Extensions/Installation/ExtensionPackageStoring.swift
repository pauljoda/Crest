import Foundation

protocol BrowserExtensionPackageStoring {
    @MainActor func stage(
        _ sourceURL: URL,
        in spaceID: SpaceID
    ) async throws -> BrowserExtensionPackage

    @MainActor func stage(
        _ package: BrowserVerifiedCRX3Package,
        in spaceID: SpaceID
    ) async throws -> BrowserExtensionPackage

    @MainActor func stage(
        _ package: BrowserVerifiedXPIPackage,
        in spaceID: SpaceID
    ) async throws -> BrowserExtensionPackage

    @MainActor func stage(
        _ package: BrowserLocalExtensionPackage,
        in spaceID: SpaceID
    ) async throws -> BrowserExtensionPackage

    @MainActor func stageVerifiedChromeResource(
        _ sourceURL: URL,
        extensionID: BrowserChromeExtensionID,
        in spaceID: SpaceID
    ) async throws -> BrowserExtensionPackage

    func resourceURL(
        packageName: String,
        in spaceID: SpaceID
    ) throws -> URL

    func discard(_ package: BrowserExtensionPackage)

    func removePackage(
        packageName: String,
        in spaceID: SpaceID
    ) throws

    func removePackages(in spaceID: SpaceID) throws
}
