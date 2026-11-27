import Foundation

/// Where each Space's downloads go on this device, which the core's device
/// store keeps: asked for each time, a folder the person chose, kept as the
/// platform's bookmark of it, or the platform's own Downloads folder. A
/// chosen folder's access stays open while its Space uses it, so files keep
/// landing there and a finished one stays readable.
@MainActor
final class BrowserPlatformDownloadPreferences {
    // MARK: - Types

    /// A folder inside the app's own container needs no security scope, so
    /// starting one fails there and only a started scope is stopped.
    private struct OpenedDirectory {
        let url: URL
        let isScoped: Bool
    }

    // MARK: - Static Variables

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

    // MARK: - Variables

    private let core: CrestCore
    /// Each Space's chosen folder, with its access held open.
    private var openedDirectories: [UUID: OpenedDirectory] = [:]
    /// Folders a Space stopped using during this run. Their access stays open
    /// until the app quits, so a download still writing there finishes and the
    /// files already saved there still open.
    private var retiredDirectories: [OpenedDirectory] = []

    // MARK: - Initializers

    init(core: CrestCore) {
        self.core = core
    }

    /// Has Settings and downloads share preferences over `core`, the
    /// launch's.
    static func configure(core: CrestCore) {
        configured = BrowserPlatformDownloadPreferences(core: core)
    }

    // MARK: - Actions - Asking

    func asksWhereToSave(for spaceID: UUID) -> Bool {
        preferences(for: spaceID).asksWhereToSave
    }

    func setAsksWhereToSave(_ enabled: Bool, for spaceID: UUID) {
        var preferences = preferences(for: spaceID)
        preferences.asksWhereToSave = enabled
        keep(preferences)
    }

    // MARK: - Actions - Folder

    func directoryDisplayName(for spaceID: UUID) -> String? {
        preferences(for: spaceID).folder?.name
    }

    func setDirectoryMetadata(bookmark: Data, displayName: String, for spaceID: UUID) {
        var preferences = preferences(for: spaceID)
        preferences.folder = DownloadFolder(name: displayName, token: bookmark)
        keep(preferences)
    }

    /// Keeps `url` as the Space's folder. A folder a document picker handed
    /// over can be bookmarked only while its access is open.
    func rememberDirectory(_ url: URL, for spaceID: UUID) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(
            options: Self.bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        retireDirectory(for: spaceID)
        setDirectoryMetadata(bookmark: bookmark, displayName: Self.displayName(of: url), for: spaceID)
    }

    /// The Space's chosen folder, or nil when it has none or the folder is
    /// gone.
    func directoryURL(for spaceID: UUID) -> URL? {
        guard let bookmark = preferences(for: spaceID).folder?.token else { return nil }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark, options: Self.bookmarkResolutionOptions, relativeTo: nil,
                bookmarkDataIsStale: &isStale)
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue
            else { return nil }
            if isStale { try? rememberDirectory(url, for: spaceID) }
            return url
        } catch {
            return nil
        }
    }

    /// The Space's chosen folder with its access held open, or nil when it
    /// has none or the folder is gone. The bookmark, not the path, names the
    /// folder: one moved away and replaced by another of the same name does
    /// not take its downloads.
    func openedDirectoryURL(for spaceID: UUID) -> URL? {
        guard let url = directoryURL(for: spaceID) else {
            closeDirectory(for: spaceID)
            return nil
        }
        if let opened = openedDirectories[spaceID], opened.url.standardizedFileURL == url.standardizedFileURL {
            return opened.url
        }
        retireDirectory(for: spaceID)
        openedDirectories[spaceID] = OpenedDirectory(url: url, isScoped: url.startAccessingSecurityScopedResource())
        return url
    }

    /// Opens the chosen folder of each of `spaceIDs`, so a finished file
    /// saved in any of them can be read.
    func openDirectories(for spaceIDs: some Sequence<UUID>) {
        for spaceID in spaceIDs { _ = openedDirectoryURL(for: spaceID) }
    }

    func clearDirectory(for spaceID: UUID) {
        retireDirectory(for: spaceID)
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

    // MARK: - Mutators

    private func retireDirectory(for spaceID: UUID) {
        guard let opened = openedDirectories.removeValue(forKey: spaceID) else { return }
        retiredDirectories.append(opened)
    }

    private func closeDirectory(for spaceID: UUID) {
        guard let opened = openedDirectories.removeValue(forKey: spaceID), opened.isScoped else { return }
        opened.url.stopAccessingSecurityScopedResource()
    }
}
