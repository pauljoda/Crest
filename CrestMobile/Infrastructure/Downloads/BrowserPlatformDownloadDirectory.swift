import Foundation

enum BrowserPlatformDownloadDirectory {
    static func resolve(
        suggestedFilename: String,
        spaceID _: SpaceID,
        fileManager: FileManager = .default
    ) async -> BrowserPlatformDownloadResolution {
        let directory = URL.documentsDirectory
            .appendingPathComponent("Downloads", isDirectory: true)
        return .destination(
            BrowserDownloadDestination.availableURL(
                suggestedFilename: suggestedFilename,
                directory: directory,
                fileExists: { fileManager.fileExists(atPath: $0.path) }
            ),
            securityScopedURL: nil
        )
    }
}
