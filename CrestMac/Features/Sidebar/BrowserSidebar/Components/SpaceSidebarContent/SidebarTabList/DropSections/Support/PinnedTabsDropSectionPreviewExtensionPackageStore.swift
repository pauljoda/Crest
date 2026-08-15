import Foundation

struct PinnedTabsDropSectionPreviewExtensionPackageStore:
    BrowserExtensionPackageStoring
{
    func stage(
        _ sourceURL: URL,
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage {
        throw BrowserExtensionPackageStoreError.unsupportedSource
    }

    func stage(
        _ package: BrowserVerifiedCRX3Package,
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage {
        throw BrowserExtensionPackageStoreError.unsupportedSource
    }

    func stage(
        _ package: BrowserVerifiedXPIPackage,
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage {
        throw BrowserExtensionPackageStoreError.unsupportedSource
    }

    func stageVerifiedChromeResource(
        _ sourceURL: URL,
        extensionID: BrowserChromeExtensionID,
        in spaceID: SpaceID
    ) throws -> BrowserExtensionPackage {
        throw BrowserExtensionPackageStoreError.unsupportedSource
    }

    func resourceURL(
        packageName: String,
        in spaceID: SpaceID
    ) throws -> URL {
        throw BrowserExtensionPackageStoreError.packageMissing
    }

    func discard(_ package: BrowserExtensionPackage) {}

    func removePackage(
        packageName: String,
        in spaceID: SpaceID
    ) throws {}

    func removePackages(in spaceID: SpaceID) throws {}
}
