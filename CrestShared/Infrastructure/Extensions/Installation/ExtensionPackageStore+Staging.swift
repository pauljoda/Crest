import Foundation

@MainActor
extension BrowserExtensionPackageStore {
    func stage(_ sourceURL: URL, in spaceID: SpaceID) async throws -> BrowserExtensionPackage {
        try await stageOnWorker { try $0.stage(sourceURL, in: spaceID) }
    }

    func stage(_ package: BrowserVerifiedCRX3Package, in spaceID: SpaceID) async throws -> BrowserExtensionPackage {
        try await stageOnWorker { try $0.stage(package, in: spaceID) }
    }

    func stage(_ package: BrowserVerifiedXPIPackage, in spaceID: SpaceID) async throws -> BrowserExtensionPackage {
        try await stageOnWorker { try $0.stage(package, in: spaceID) }
    }

    func stage(_ package: BrowserLocalExtensionPackage, in spaceID: SpaceID) async throws -> BrowserExtensionPackage {
        try await stageOnWorker { try $0.stage(package, in: spaceID) }
    }

    func stageVerifiedChromeResource(
        _ sourceURL: URL, extensionID: BrowserChromeExtensionID, in spaceID: SpaceID
    ) async throws -> BrowserExtensionPackage {
        try await stageOnWorker { try $0.stageVerifiedChromeResource(sourceURL, extensionID: extensionID, in: spaceID) }
    }
}
