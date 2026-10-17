import Foundation

/// The Spaces the share sheet offers, as Crest last wrote them to the shared
/// container: their order, names, whether each is locked, the one shown
/// last, and an icon Crest rendered for each. Private browsing is never
/// listed.
struct BrowserSharedSpaceDirectory: Codable, Equatable, Sendable {
    // MARK: - Types

    struct Space: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        let name: String
        let isLocked: Bool
    }

    // MARK: - Static Variables

    private static let fileName = "shared-spaces.json"
    private static let iconFolderName = "shared-space-icons"

    // MARK: - Variables

    let spaces: [Space]
    /// The Space a window showed last, which the share sheet selects first.
    let lastSpaceID: UUID?

    // MARK: - Actions - Reading

    /// The directory Crest last wrote, or nil before it wrote one.
    static func read(from container: BrowserLinkSharingContainer) -> BrowserSharedSpaceDirectory? {
        guard let data = try? Data(contentsOf: fileURL(in: container)) else { return nil }
        return try? JSONDecoder().decode(BrowserSharedSpaceDirectory.self, from: data)
    }

    /// Where the icon of `spaceID` is, whether or not Crest rendered one.
    static func iconURL(for spaceID: UUID, in container: BrowserLinkSharingContainer) -> URL {
        iconFolderURL(in: container).appending(path: "\(spaceID.uuidString).png")
    }

    /// The Space the share sheet selects first: the one shown last while it
    /// is still listed, otherwise the first.
    var initialSpaceID: UUID? {
        spaces.first { $0.id == lastSpaceID }?.id ?? spaces.first?.id
    }

    // MARK: - Actions - Writing

    /// Replaces the stored directory and its icons with this one, keeping
    /// icons only for the Spaces it lists.
    func write(to container: BrowserLinkSharingContainer, icons: [UUID: Data]) throws {
        let fileManager = FileManager.default
        let iconFolder = Self.iconFolderURL(in: container)
        try fileManager.createDirectory(at: iconFolder, withIntermediateDirectories: true)
        let listed = Set(spaces.map(\.id))
        for stale in (try? fileManager.contentsOfDirectory(at: iconFolder, includingPropertiesForKeys: nil)) ?? []
        where !listed.contains(where: { stale.lastPathComponent == "\($0.uuidString).png" }) {
            try? fileManager.removeItem(at: stale)
        }
        for (spaceID, icon) in icons where listed.contains(spaceID) {
            try icon.write(to: Self.iconURL(for: spaceID, in: container), options: .atomic)
        }
        try JSONEncoder().encode(self).write(to: Self.fileURL(in: container), options: .atomic)
    }

    // MARK: - Actions - Locations

    private static func fileURL(in container: BrowserLinkSharingContainer) -> URL {
        container.directory.appending(path: fileName)
    }

    private static func iconFolderURL(in container: BrowserLinkSharingContainer) -> URL {
        container.directory.appending(path: iconFolderName, directoryHint: .isDirectory)
    }
}
