import Foundation

protocol BrowserExtensionPackageStoring {
    func stage(
        _ sourceURL: URL,
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage

    func stage(
        _ package: BrowserVerifiedCRX3Package,
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage

    func stage(
        _ package: BrowserVerifiedXPIPackage,
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage

    func stage(
        _ package: BrowserLocalExtensionPackage,
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage

    func stageVerifiedChromeResource(
        _ sourceURL: URL,
        extensionID: BrowserChromeExtensionID,
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage

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
