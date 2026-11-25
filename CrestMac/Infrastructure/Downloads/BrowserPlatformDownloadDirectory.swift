import AppKit
import Foundation

@MainActor
enum BrowserPlatformDownloadDirectory {
    static func resolve(
        suggestedFilename: String,
        spaceID: UUID,
        forcesPrompt: Bool = false,
        fileManager: FileManager = .default
    ) async -> any BrowserPlatformDownloadResolution {
        let safeFilename = BrowserDownloadDestination.safeFilename(
            from: suggestedFilename
        )
        let preferences = BrowserPlatformDownloadPreferences.shared
        if forcesPrompt || preferences.asksWhereToSave(for: spaceID) {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = safeFilename
            panel.title = String(localized: "Save Download")
            panel.prompt = String(localized: "Save")
            let response = await withCheckedContinuation { continuation in
                panel.begin { continuation.resume(returning: $0) }
            }
            guard response == .OK, let destination = panel.url else {
                return .cancelled
            }
            return .destination(
                destination,
                securityScopedURL: destination
            )
        }

        if let customDirectory = preferences.directoryURL(for: spaceID) {
            return .destination(
                BrowserDownloadDestination.availableURL(
                    suggestedFilename: safeFilename,
                    directory: customDirectory,
                    fileExists: { fileManager.fileExists(atPath: $0.path) }
                ),
                securityScopedURL: customDirectory
            )
        }
        guard preferences.directoryDisplayName(for: spaceID) == nil else {
            return .unavailable
        }

        guard
            let downloadsDirectory = fileManager.urls(
                for: .downloadsDirectory,
                in: .userDomainMask
            ).first
        else { return .unavailable }
        return .destination(
            BrowserDownloadDestination.availableURL(
                suggestedFilename: safeFilename,
                directory: downloadsDirectory,
                fileExists: { fileManager.fileExists(atPath: $0.path) }
            ),
            securityScopedURL: nil
        )
    }
}
