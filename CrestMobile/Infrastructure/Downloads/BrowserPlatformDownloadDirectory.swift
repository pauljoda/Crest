import Foundation

@MainActor
enum BrowserPlatformDownloadDirectory {
    /// A file goes to the folder the person chose for the Space, such as the
    /// Downloads folder the Files app shows, or to Crest's own Downloads
    /// folder until they choose one.
    static func resolve(
        suggestedFilename: String,
        spaceID: UUID,
        forcesPrompt _: Bool = false,
        fileManager: FileManager = .default
    ) async -> any BrowserPlatformDownloadResolution {
        let preferences = BrowserPlatformDownloadPreferences.shared
        if let chosenDirectory = preferences.openedDirectoryURL(for: spaceID) {
            return destination(
                for: suggestedFilename, in: chosenDirectory, fileManager: fileManager)
        }
        guard preferences.directoryDisplayName(for: spaceID) == nil else {
            return .unavailable
        }
        return destination(
            for: suggestedFilename,
            in: URL.documentsDirectory.appendingPathComponent("Downloads", isDirectory: true),
            fileManager: fileManager)
    }

    private static func destination(
        for suggestedFilename: String,
        in directory: URL,
        fileManager: FileManager
    ) -> any BrowserPlatformDownloadResolution {
        .destination(
            BrowserDownloadDestination.availableURL(
                suggestedFilename: suggestedFilename,
                directory: directory,
                fileExists: { fileManager.fileExists(atPath: $0.path) }
            ),
            securityScopedURL: nil
        )
    }
}
