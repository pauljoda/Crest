import Foundation

enum BrowserHistoryMigration {
    static let maximumDatabaseByteCount = 512 * 1_024 * 1_024

    static func read(
        from url: URL,
        source: BrowserHistoryMigrationSource,
        importedAt: Date = .now
    ) async throws -> BrowserPortableImport {
        try await Task.detached {
            try readSynchronously(
                from: url,
                source: source,
                importedAt: importedAt
            )
        }.value
    }

    private static func readSynchronously(
        from url: URL,
        source: BrowserHistoryMigrationSource,
        importedAt: Date
    ) throws -> BrowserPortableImport {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        } catch {
            throw BrowserHistoryMigrationError.missingFile
        }
        guard values.isRegularFile == true else {
            throw BrowserHistoryMigrationError.missingFile
        }
        guard values.fileSize ?? 0 <= maximumDatabaseByteCount else {
            throw BrowserHistoryMigrationError.fileTooLarge
        }

        let database = try BrowserHistorySQLiteDatabase(url: url)
        let records = try database.records(for: source)
        let history = BrowserHistoryMigrationPolicy.normalizedHistory(
            from: records,
            source: source
        )
        guard !history.isEmpty else {
            throw BrowserHistoryMigrationError.noImportableHistory
        }

        let temporarySpace = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: String(localized: source.importedSpaceName),
            symbol: source.symbol,
            accent: source.accent,
            folders: [],
            tabs: [],
            archivedTabs: [],
            history: history,
            browsingPreferences: .default,
            credentialPreferences: .default,
            selectedTabID: nil
        )
        do {
            return try BrowserPortableArchive(
                session: BrowserSession(
                    spaces: [temporarySpace],
                    selectedSpaceID: temporarySpace.id
                ),
                exportedAt: importedAt
            ).materialize()
        } catch {
            throw BrowserHistoryMigrationError.unrecognizedDatabase
        }
    }

}
