import Foundation

/// Where each Space's downloads go when the person chose a folder for them,
/// remembered as a bookmark the shell can reach again.
@MainActor
final class BrowserPlatformDownloadPreferences {
    // MARK: - Types

    private struct VolatileRecord {
        var asksWhereToSave = false
        var bookmark: Data?
        var displayName: String?
    }

    /// A folder inside Crest's own container needs no security scope, so
    /// starting one fails there and only a started scope is stopped.
    private struct OpenedDirectory {
        let url: URL
        let isScoped: Bool
    }

    // MARK: - Static Variables

    static let shared = BrowserPlatformDownloadPreferences()

    private static let keyPrefix = "browser.download.space."

    // MARK: - Variables

    private let defaults: UserDefaults?
    private var volatileRecords: [UUID: VolatileRecord] = [:]

    /// Each Space's chosen folder, with its access held open so files keep
    /// landing there and a finished one stays readable while Quick Look or
    /// the share sheet shows it.
    private var openedDirectories: [UUID: OpenedDirectory] = [:]

    /// Folders a Space stopped using during this run. Their access stays
    /// open until Crest quits, so a download still writing there finishes
    /// and the files already saved there still open.
    private var retiredDirectories: [OpenedDirectory] = []

    // MARK: - Initializers

    init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
        } else if BrowserLaunchEnvironment.current.requiresIsolation {
            self.defaults = nil
        } else {
            self.defaults = .standard
        }
    }

    // MARK: - Actions - Asking

    func asksWhereToSave(for spaceID: UUID) -> Bool {
        guard let defaults else {
            return volatileRecords[spaceID]?.asksWhereToSave ?? false
        }
        return defaults.bool(forKey: key("asksWhere", for: spaceID))
    }

    // MARK: - Actions - Folder

    func directoryDisplayName(for spaceID: UUID) -> String? {
        guard let defaults else {
            return volatileRecords[spaceID]?.displayName
        }
        return defaults.string(forKey: key("directoryName", for: spaceID))
    }

    func directoryURL(for spaceID: UUID) -> URL? {
        let bookmark: Data?
        if let defaults {
            bookmark = defaults.data(
                forKey: key("directoryBookmark", for: spaceID)
            )
        } else {
            bookmark = volatileRecords[spaceID]?.bookmark
        }
        guard let bookmark else { return nil }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: Self.bookmarkResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard Self.isExistingDirectory(url) else { return nil }
            if isStale {
                try? rememberDirectory(url, for: spaceID)
            }
            return url
        } catch {
            return nil
        }
    }

    /// The Space's chosen folder with its access held open, or nil when it
    /// has none or the folder is gone.
    func openedDirectoryURL(for spaceID: UUID) -> URL? {
        // The bookmark, not the path, names the folder: one moved away and
        // replaced by another of the same name must not take its downloads.
        guard let url = directoryURL(for: spaceID) else {
            closeDirectory(for: spaceID)
            return nil
        }
        if let opened = openedDirectories[spaceID], opened.url.standardizedFileURL == url.standardizedFileURL {
            return opened.url
        }
        retireDirectory(for: spaceID)
        openedDirectories[spaceID] = OpenedDirectory(
            url: url, isScoped: url.startAccessingSecurityScopedResource())
        return url
    }

    /// Opens the chosen folder of each of `spaceIDs`, so a finished file
    /// saved in any of them can be read.
    func openDirectories(for spaceIDs: some Sequence<UUID>) {
        for spaceID in spaceIDs {
            _ = openedDirectoryURL(for: spaceID)
        }
    }

    // MARK: - Mutators

    func setAsksWhereToSave(_ enabled: Bool, for spaceID: UUID) {
        guard let defaults else {
            var record = volatileRecords[spaceID] ?? VolatileRecord()
            record.asksWhereToSave = enabled
            volatileRecords[spaceID] = record
            return
        }
        defaults.set(enabled, forKey: key("asksWhere", for: spaceID))
    }

    func setDirectoryMetadata(
        bookmark: Data,
        displayName: String,
        for spaceID: UUID
    ) {
        guard let defaults else {
            var record = volatileRecords[spaceID] ?? VolatileRecord()
            record.bookmark = bookmark
            record.displayName = displayName
            volatileRecords[spaceID] = record
            return
        }
        defaults.set(bookmark, forKey: key("directoryBookmark", for: spaceID))
        defaults.set(displayName, forKey: key("directoryName", for: spaceID))
    }

    func rememberDirectory(_ url: URL, for spaceID: UUID) throws {
        // A folder a document picker handed over can be bookmarked only while
        // its access is open.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(
            options: Self.bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        retireDirectory(for: spaceID)
        setDirectoryMetadata(
            bookmark: bookmark,
            displayName: Self.displayName(of: url),
            for: spaceID
        )
    }

    func clearDirectory(for spaceID: UUID) {
        retireDirectory(for: spaceID)
        guard let defaults else {
            var record = volatileRecords[spaceID] ?? VolatileRecord()
            record.bookmark = nil
            record.displayName = nil
            volatileRecords[spaceID] = record
            return
        }
        defaults.removeObject(forKey: key("directoryBookmark", for: spaceID))
        defaults.removeObject(forKey: key("directoryName", for: spaceID))
    }

    private func retireDirectory(for spaceID: UUID) {
        guard let opened = openedDirectories.removeValue(forKey: spaceID) else { return }
        retiredDirectories.append(opened)
    }

    private func closeDirectory(for spaceID: UUID) {
        guard let opened = openedDirectories.removeValue(forKey: spaceID), opened.isScoped else { return }
        opened.url.stopAccessingSecurityScopedResource()
    }

    private static func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    private func key(_ suffix: String, for spaceID: UUID) -> String {
        Self.keyPrefix
            + spaceID.uuidString.lowercased()
            + "."
            + suffix
    }
}
