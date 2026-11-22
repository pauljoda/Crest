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

/// Where each Space's downloads go on this Mac, which the core's device store
/// keeps: asked for each time, or a folder the person chose, kept as its
/// security-scoped bookmark, or the Downloads folder.
@MainActor
final class BrowserPlatformDownloadPreferences {
    /// The preferences Settings and downloads share: over the launch's core
    /// once the launch configures them, and before that over a memory-only
    /// core of their own, made on first use, as previews and tests use.
    static var shared: BrowserPlatformDownloadPreferences {
        if let configured { return configured }
        let preferences = BrowserPlatformDownloadPreferences(core: CrestCore())
        configured = preferences
        return preferences
    }

    /// The preferences `shared` answers, once there are some.
    private static var configured: BrowserPlatformDownloadPreferences?

    private let core: CrestCore

    init(core: CrestCore) {
        self.core = core
    }

    /// Has Settings and downloads share preferences over `core`, the
    /// launch's.
    static func configure(core: CrestCore) {
        configured = BrowserPlatformDownloadPreferences(core: core)
    }

    func asksWhereToSave(for spaceID: UUID) -> Bool {
        preferences(for: spaceID).asksWhereToSave
    }

    func setAsksWhereToSave(_ enabled: Bool, for spaceID: UUID) {
        var preferences = preferences(for: spaceID)
        preferences.asksWhereToSave = enabled
        keep(preferences)
    }

    func directoryDisplayName(for spaceID: UUID) -> String? {
        preferences(for: spaceID).folder?.name
    }

    func setDirectoryMetadata(bookmark: Data, displayName: String, for spaceID: UUID) {
        var preferences = preferences(for: spaceID)
        preferences.folder = DownloadFolder(name: displayName, token: bookmark)
        keep(preferences)
    }

    func rememberDirectory(_ url: URL, for spaceID: UUID) throws {
        let bookmark = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        setDirectoryMetadata(
            bookmark: bookmark,
            displayName: url.lastPathComponent,
            for: spaceID
        )
    }

    func directoryURL(for spaceID: UUID) -> URL? {
        guard let bookmark = preferences(for: spaceID).folder?.token else { return nil }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var isDirectory: ObjCBool = false
            guard
                FileManager.default.fileExists(
                    atPath: url.path,
                    isDirectory: &isDirectory
                ), isDirectory.boolValue
            else {
                return nil
            }
            if isStale {
                try? rememberDirectory(url, for: spaceID)
            }
            return url
        } catch {
            return nil
        }
    }

    func clearDirectory(for spaceID: UUID) {
        var preferences = preferences(for: spaceID)
        preferences.folder = nil
        keep(preferences)
    }

    // MARK: - Actions - Core

    /// Where the Space `spaceID`'s downloads go, as the core keeps it.
    private func preferences(for spaceID: UUID) -> SpaceDownloadPreferences {
        core.state.downloadPreferences.first { $0.spaceID == spaceID }
            ?? SpaceDownloadPreferences(spaceID: spaceID, asksWhereToSave: false, folder: nil)
    }

    private func keep(_ preferences: SpaceDownloadPreferences) {
        _ = try? core.send(SetSpaceDownloads(preferences: preferences))
    }
}
