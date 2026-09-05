import Foundation

struct BrowserPortableArchive: Codable, Equatable, Sendable {
    static let formatIdentifier = "com.pauldavis.crest.browser-data"
    static let currentSchemaVersion = 4
    static let maximumEncodedByteCount = 50 * 1_024 * 1_024
    static let maximumSpaceCount = 64
    static let defaultFilename = "Crest Browser Data.json"

    let format: String
    let schemaVersion: Int
    let exportedAt: Date
    let spaces: [PortableSpace]

    init(session: BrowserSession, exportedAt: Date = .now) {
        format = Self.formatIdentifier
        schemaVersion = Self.currentSchemaVersion
        self.exportedAt = exportedAt
        spaces = session.spaces.map(PortableSpace.init)
    }

    func materialize() throws -> BrowserPortableImport {
        guard format == Self.formatIdentifier else {
            throw BrowserPortableArchiveError.unrecognizedFormat
        }
        guard (1...Self.currentSchemaVersion).contains(schemaVersion) else {
            throw BrowserPortableArchiveError.unsupportedSchemaVersion(schemaVersion)
        }
        guard !spaces.isEmpty, spaces.count <= Self.maximumSpaceCount else {
            throw BrowserPortableArchiveError.invalidContents
        }

        let importedSpaces = try spaces.map { try $0.materialize() }
        let summary = BrowserPortableImportSummary(
            spaceCount: importedSpaces.count,
            folderCount: importedSpaces.reduce(0) { $0 + $1.folders.count },
            liveTabCount: importedSpaces.reduce(0) { $0 + $1.tabs.count },
            archivedTabCount: importedSpaces.reduce(0) { $0 + $1.archivedTabs.count },
            historyEntryCount: importedSpaces.reduce(0) { $0 + $1.history.count }
        )
        return BrowserPortableImport(spaces: importedSpaces, summary: summary)
    }

}
